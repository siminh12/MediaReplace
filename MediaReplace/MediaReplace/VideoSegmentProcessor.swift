// VideoSegmentProcessor.swift
// MediaReplace — clean-room rewrite.
// Local video processing with AVFoundation only: AVAsset +
// AVMutableComposition + insertTimeRange + AVMutableVideoComposition +
// AVMutableAudioMix, exported by AVAssetExportSession.
// Two export presets: passthrough and 1920x1080. No networking.

import AVFoundation
import Foundation

/// Export quality for processed video.
enum ExportQuality: String, CaseIterable {
    case passthrough
    case hd1080

    var presetName: String {
        switch self {
        case .passthrough: return AVAssetExportPresetPassthrough
        case .hd1080: return AVAssetExportPreset1920x1080
        }
    }

    var displayName: String {
        switch self {
        case .passthrough: return "原画质直通"
        case .hd1080: return "1080p"
        }
    }
}

/// Cuts a replacement video to a draft's time ranges and exports it.
final class VideoSegmentProcessor {

    /// Duration of a video file in seconds, or nil if it cannot be read.
    static func duration(of url: URL) -> Double? {
        let asset = AVAsset(url: url)
        guard asset.isReadable else { return nil }
        let seconds = CMTimeGetSeconds(asset.duration)
        guard seconds.isFinite, seconds > 0 else { return nil }
        return seconds
    }

    /// Process `sourceURL` and write the result to a fresh temporary file.
    ///
    /// - Parameters:
    ///   - sourceURL: the replacement video the user picked.
    ///   - metadata: draft metadata; its target ranges decide the cuts.
    ///   - enableSegmentProcess: when false, the whole video is exported
    ///     as one segment instead of being cut.
    ///   - quality: export preset (passthrough or 1920x1080).
    ///   - progress: called on the main thread with 0...1.
    ///   - completion: called on the main thread with the output file URL
    ///     or a `ProcessError`.
    static func process(
        sourceURL: URL,
        metadata: DraftMetadata?,
        enableSegmentProcess: Bool,
        quality: ExportQuality,
        progress: @escaping (Float) -> Void,
        completion: @escaping (Result<URL, ProcessError>) -> Void
    ) {
        let asset = AVAsset(url: sourceURL)
        guard asset.isReadable else {
            DispatchQueue.main.async { completion(.failure(.assetNotReadable)) }
            return
        }
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            DispatchQueue.main.async { completion(.failure(.noVideoTrack)) }
            return
        }

        let sourceDuration = CMTimeGetSeconds(asset.duration)
        guard sourceDuration.isFinite, sourceDuration > 0 else {
            DispatchQueue.main.async { completion(.failure(.invalidTimeRange)) }
            return
        }

        // Decide the segments to keep.
        var ranges: [(start: Double, end: Double)] = []
        if enableSegmentProcess, let metadata = metadata, metadata.hasSegments {
            ranges = metadata.segmentRanges.filter { $0.end > $0.start }
        }
        if ranges.isEmpty {
            ranges = [(0, sourceDuration)]
        }
        // Clamp every range to the source video.
        ranges = ranges.compactMap { range in
            let start = max(0, min(range.start, sourceDuration))
            let end = max(start, min(range.end, sourceDuration))
            return end > start ? (start, end) : nil
        }
        guard !ranges.isEmpty else {
            DispatchQueue.main.async { completion(.failure(.invalidTimeRange)) }
            return
        }

        // Build the composition.
        let composition = AVMutableComposition()
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            DispatchQueue.main.async { completion(.failure(.exportSessionUnavailable)) }
            return
        }
        let compositionAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )
        let audioTrack = asset.tracks(withMediaType: .audio).first

        var cursor = CMTime.zero
        do {
            for range in ranges {
                let timeRange = CMTimeRange(
                    start: CMTime(seconds: range.start, preferredTimescale: 600),
                    duration: CMTime(seconds: range.end - range.start, preferredTimescale: 600)
                )
                try compositionVideoTrack.insertTimeRange(timeRange, of: videoTrack, at: cursor)
                if let audioTrack = audioTrack, let compositionAudioTrack = compositionAudioTrack {
                    try compositionAudioTrack.insertTimeRange(timeRange, of: audioTrack, at: cursor)
                }
                cursor = CMTimeAdd(cursor, timeRange.duration)
            }
        } catch {
            DispatchQueue.main.async { completion(.failure(.outputWriteFailed(error.localizedDescription))) }
            return
        }

        // Video composition: keep the source orientation and size.
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = videoTrack.naturalSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
        layerInstruction.setTransform(videoTrack.preferredTransform, at: .zero)
        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]

        // Audio mix: pass the audio through unchanged.
        let audioMix = AVMutableAudioMix()
        if let audioTrack = audioTrack {
            let audioMixInput = AVMutableAudioMixInputParameters(track: audioTrack)
            audioMixInput.setVolume(1.0, at: .zero)
            audioMix.inputParameters = [audioMixInput]
        }

        // Output file.
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MediaReplace-\(UUID().uuidString)")
            .appendingPathExtension("mp4")
        try? FileManager.default.removeItem(at: outputURL)

        // Export. Passthrough cannot re-encode a composition, so:
        // - whole-video export (no cutting) exports the source asset
        //   directly, where passthrough genuinely works;
        // - segmented export uses the composition and falls back to the
        //   highest-quality preset when passthrough was requested.
        let wholeVideo = ranges.count == 1
            && ranges[0].start == 0
            && abs(ranges[0].end - sourceDuration) < 0.01
        var preset = quality.presetName
        var exportAsset: AVAsset = asset
        var useComposition = false
        if wholeVideo {
            exportAsset = asset
        } else {
            if preset == AVAssetExportPresetPassthrough {
                preset = AVAssetExportPresetHighestQuality
            }
            exportAsset = composition
            useComposition = true
        }
        var exportSession = AVAssetExportSession(asset: exportAsset, presetName: preset)
        if exportSession == nil {
            preset = AVAssetExportPresetHighestQuality
            exportSession = AVAssetExportSession(asset: exportAsset, presetName: preset)
        }
        guard let session = exportSession else {
            DispatchQueue.main.async { completion(.failure(.exportSessionUnavailable)) }
            return
        }
        session.outputURL = outputURL
        session.outputFileType = .mp4
        if useComposition {
            session.videoComposition = videoComposition
            session.audioMix = audioMix
        }
        session.shouldOptimizeForNetworkUse = false

        // Progress polling (exportAsynchronously has no progress callback).
        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            DispatchQueue.main.async { progress(session.progress) }
        }

        session.exportAsynchronously {
            timer.invalidate()
            DispatchQueue.main.async {
                switch session.status {
                case .completed:
                    progress(1.0)
                    completion(.success(outputURL))
                case .cancelled:
                    completion(.failure(.exportCancelled))
                case .failed:
                    let detail = session.error?.localizedDescription ?? "未知错误"
                    completion(.failure(.exportFailed(detail)))
                default:
                    completion(.failure(.exportFailed("导出未完成（状态：\(session.status.rawValue)）")))
                }
            }
        }
    }
}
