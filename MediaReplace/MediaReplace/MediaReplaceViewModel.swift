// MediaReplaceViewModel.swift
// MediaReplace — clean-room rewrite.
// App state: platform selection, draft list, selected draft, replacement
// video, segment processing switch, progress and result state.
// The notice text is a fixed local string; nothing is fetched remotely.

import AVFoundation
import Foundation
import Photos
import SwiftUI

@MainActor
final class MediaReplaceViewModel: ObservableObject {

    // MARK: - Notice (local only, never fetched from a server)

    /// Local announcement shown at the top of the main screen.
    let noticeText = "本地媒体替换工具：扫描草稿、选择替换视频、分段处理后写回草稿。无联网，无激活。"

    // MARK: - Platform & drafts

    @Published var selectedPlatform: PlatformChannel = .douyin
    @Published var drafts: [DraftVideo] = []
    @Published var selectedDraft: DraftVideo?
    @Published var scanMessage: String?
    @Published var isScanning = false

    /// Folder the user picked by hand (document picker). Kept so the list
    /// can be refreshed without asking again.
    @Published var pickedFolderURL: URL?

    // MARK: - Replacement & processing

    @Published var replacementVideoURL: URL?
    @Published var replacementInfo: MediaFileInfo?
    @Published var showSegmentSheet = false
    @Published var enableSegmentProcess = true
    @Published var isProcessingSegment = false
    @Published var processingProgress: Float = 0
    @Published var exportQuality: ExportQuality = .passthrough

    // MARK: - Results

    @Published var replaceState: ReplaceState = .idle
    @Published var deleteState: DeleteState = .idle

    /// A processed video ready to save/share in local-only mode.
    @Published var processedOutputURL: URL?
    @Published var showShareSheet = false

    var selectedPlatformDrafts: [DraftVideo] {
        drafts.filter { $0.platform == selectedPlatform }
    }

    // MARK: - Scanning

    /// Scan the app containers. On a stock phone this finds nothing,
    /// because the sandbox blocks other apps' containers; the empty state
    /// in the UI explains why and offers the folder picker instead.
    func scanDrafts() {
        isScanning = true
        scanMessage = nil
        let platforms = PlatformChannel.allCases
        DispatchQueue.global(qos: .userInitiated).async {
            let found = DraftScanner.scanContainers(platforms: platforms)
            DispatchQueue.main.async {
                self.isScanning = false
                self.drafts = found
                if found.isEmpty {
                    self.scanMessage = "没有找到草稿。未越狱的手机无法直接读取其他 App 的容器，请使用“选择草稿文件夹”手动指定草稿目录，或使用“仅本地处理并导出”模式。"
                } else {
                    self.scanMessage = "共找到 \(found.count) 个草稿视频。"
                }
            }
        }
    }

    /// Scan a folder the user picked with the document picker.
    func scanPickedFolder(_ folderURL: URL) {
        pickedFolderURL = folderURL
        isScanning = true
        scanMessage = nil
        let platform = DraftScanner.platformGuess(for: folderURL) ?? selectedPlatform
        DispatchQueue.global(qos: .userInitiated).async {
            // Hold security-scoped access for the whole scan, not just
            // until this function returns.
            let accessGranted = folderURL.startAccessingSecurityScopedResource()
            defer { if accessGranted { folderURL.stopAccessingSecurityScopedResource() } }
            let found = DraftScanner.scanFolder(folderURL, platform: platform)
            DispatchQueue.main.async {
                self.isScanning = false
                self.drafts = found
                if found.isEmpty {
                    self.scanMessage = "所选文件夹中没有找到草稿视频。"
                } else {
                    self.scanMessage = "在所选文件夹中找到 \(found.count) 个草稿视频。"
                }
            }
        }
    }

    /// Refresh the current source (picked folder, or containers).
    func refresh() {
        if let folderURL = pickedFolderURL {
            scanPickedFolder(folderURL)
        } else {
            scanDrafts()
        }
    }

    // MARK: - Replacement video

    func setReplacementVideo(url: URL) {
        replacementVideoURL = url
        let duration = VideoSegmentProcessor.duration(of: url)
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        replacementInfo = MediaFileInfo(
            url: url,
            fileName: url.lastPathComponent,
            durationSeconds: duration,
            fileSize: size.map { Int64($0) }
        )
        replaceState = .idle
    }

    func clearReplacementVideo() {
        replacementVideoURL = nil
        replacementInfo = nil
        replaceState = .idle
    }

    // MARK: - Replace flow

    /// Process the replacement video and write it over the selected draft.
    /// The original draft is first backed up as a `.bak` file.
    func startReplace() {
        guard let draft = selectedDraft, let sourceURL = replacementVideoURL else { return }
        isProcessingSegment = true
        processingProgress = 0
        replaceState = .processing

        VideoSegmentProcessor.process(
            sourceURL: sourceURL,
            metadata: draft.metadata,
            enableSegmentProcess: enableSegmentProcess,
            quality: exportQuality,
            progress: { [weak self] value in
                self?.processingProgress = value
            },
            completion: { [weak self] result in
                guard let self = self else { return }
                self.isProcessingSegment = false
                switch result {
                case .success(let processedURL):
                    do {
                        try ReplaceEngine.replaceDraft(targetURL: draft.fileURL, withProcessedVideo: processedURL)
                        self.replaceState = .succeeded
                        ReplaceEngine.removeTemporaryFile(at: processedURL)
                        self.refresh()
                    } catch {
                        self.replaceState = .failed(error.localizedDescription)
                        ReplaceEngine.removeTemporaryFile(at: processedURL)
                    }
                case .failure(let error):
                    self.replaceState = .failed(error.localizedDescription)
                }
            }
        )
    }

    // MARK: - Local-only mode (no draft needed)

    /// Process the replacement video and hand the result to the share
    /// sheet, so it can be saved to Photos or to Files. Works on any phone.
    func exportLocally() {
        guard let sourceURL = replacementVideoURL else { return }
        isProcessingSegment = true
        processingProgress = 0
        replaceState = .processing

        VideoSegmentProcessor.process(
            sourceURL: sourceURL,
            metadata: selectedDraft?.metadata,
            enableSegmentProcess: enableSegmentProcess,
            quality: exportQuality,
            progress: { [weak self] value in
                self?.processingProgress = value
            },
            completion: { [weak self] result in
                guard let self = self else { return }
                self.isProcessingSegment = false
                switch result {
                case .success(let processedURL):
                    self.processedOutputURL = processedURL
                    self.replaceState = .succeeded
                    self.showShareSheet = true
                case .failure(let error):
                    self.replaceState = .failed(error.localizedDescription)
                }
            }
        )
    }

    /// Save a processed video to the photo library.
    func saveToPhotoLibrary(url: URL, completion: @escaping (Bool, String?) -> Void) {
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { completion(false, "未获得相册写入权限") }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }) { success, error in
                DispatchQueue.main.async { completion(success, error?.localizedDescription) }
            }
        }
    }

    // MARK: - Delete

    func deleteDraft(_ draft: DraftVideo) {
        do {
            try ReplaceEngine.deleteDraft(at: draft.fileURL)
            deleteState = .succeeded
            drafts.removeAll { $0 == draft }
            if selectedDraft == draft { selectedDraft = nil }
        } catch {
            deleteState = .failed(error.localizedDescription)
        }
    }
}
