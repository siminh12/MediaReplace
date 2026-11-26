// DraftScanner.swift
// MediaReplace — clean-room rewrite.
// Finds draft videos in other apps' containers (jailbroken / sideloaded
// environment only) or inside a folder the user picks by hand.
// Reads draft JSON metadata: SourceTimeRange / TargetTimeRange /
// Duration / StartTime / EndTime. No networking of any kind.

import Foundation

/// Scans for draft videos and parses their JSON metadata.
final class DraftScanner {

    /// Root of the per-app data containers on iOS.
    static let containersRoot = "/var/mobile/Containers/Data/Application"

    /// Key inside `.com.apple.mobile_container_manager.metadata.plist`
    /// that identifies which app owns a container.
    private static let metadataFileName = ".com.apple.mobile_container_manager.metadata.plist"
    private static let metadataIdentifierKey = "MCMMetadataIdentifier"

    private static let videoExtensions: Set<String> = ["mp4", "mov", "m4v"]

    // MARK: - Container scanning (needs elevated access)

    /// Enumerate every app container, identify its owner from the metadata
    /// plist, and collect draft videos for the requested platforms.
    /// On a stock, non-jailbroken phone this returns an empty list because
    /// the sandbox blocks reading other apps' containers.
    static func scanContainers(platforms: [PlatformChannel]) -> [DraftVideo] {
        let rootURL = URL(fileURLWithPath: containersRoot)
        let fileManager = FileManager.default
        guard let containerURLs = try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var results: [DraftVideo] = []
        for containerURL in containerURLs {
            guard let bundleID = bundleIdentifier(forContainerAt: containerURL) else {
                continue
            }
            for platform in platforms where platform.bundleIdentifiers.contains(bundleID) {
                results.append(contentsOf: scanContainer(containerURL, platform: platform))
            }
        }
        return results.sorted { ($0.modificationDate ?? .distantPast) > ($1.modificationDate ?? .distantPast) }
    }

    /// Read the metadata plist of one container and return its bundle id.
    static func bundleIdentifier(forContainerAt containerURL: URL) -> String? {
        let plistURL = containerURL.appendingPathComponent(metadataFileName)
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil
              ) as? [String: Any] else {
            return nil
        }
        return plist[metadataIdentifierKey] as? String
    }

    private static func scanContainer(_ containerURL: URL, platform: PlatformChannel) -> [DraftVideo] {
        var results: [DraftVideo] = []
        for relativePath in platform.relativeDraftPaths {
            let folderURL = containerURL.appendingPathComponent(relativePath)
            results.append(contentsOf: scanFolder(folderURL, platform: platform))
        }
        return results
    }

    // MARK: - Folder scanning (user-picked folder)

    /// Scan a folder the user chose with the document picker. The caller
    /// must hold security-scoped access to `folderURL` while this runs.
    /// `platform` is only used as a label; pass `.douyin` when unknown.
    static func scanFolder(_ folderURL: URL, platform: PlatformChannel) -> [DraftVideo] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var results: [DraftVideo] = []
        for case let fileURL as URL in enumerator {
            guard videoExtensions.contains(fileURL.pathExtension.lowercased()) else { continue }
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]),
                  values.isRegularFile == true else { continue }
            let metadata = metadata(forVideoAt: fileURL)
            results.append(DraftVideo(
                id: UUID(),
                platform: platform,
                fileURL: fileURL,
                fileName: fileURL.lastPathComponent,
                fileSize: Int64(values.fileSize ?? 0),
                modificationDate: values.contentModificationDate,
                metadata: metadata
            ))
        }
        return results.sorted { ($0.modificationDate ?? .distantPast) > ($1.modificationDate ?? .distantPast) }
    }

    /// Guess the platform of a user-picked folder from its path, if possible.
    static func platformGuess(for folderURL: URL) -> PlatformChannel? {
        let path = folderURL.path.lowercased()
        if path.contains("aweme") || path.contains("draft") { return .douyin }
        if path.contains("gifshow") { return .kuaishou }
        if path.contains("post") { return .xiaohongshu }
        return nil
    }

    // MARK: - Draft JSON metadata

    /// Look for a JSON metadata file next to a draft video and parse it.
    /// Accepts a same-name `.json` file, or any `.json` file in the same
    /// folder that mentions the video file name.
    static func metadata(forVideoAt videoURL: URL) -> DraftMetadata? {
        let folderURL = videoURL.deletingLastPathComponent()
        let fileManager = FileManager.default

        let sameNameJSON = videoURL.deletingPathExtension().appendingPathExtension("json")
        if fileManager.fileExists(atPath: sameNameJSON.path),
           let data = try? Data(contentsOf: sameNameJSON),
           let parsed = parseMetadataJSON(data) {
            return parsed
        }

        guard let siblings = try? fileManager.contentsOfDirectory(
            at: folderURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return nil }

        for sibling in siblings where sibling.pathExtension.lowercased() == "json" {
            guard let data = try? Data(contentsOf: sibling) else { continue }
            let text = String(decoding: data, as: UTF8.self)
            guard text.contains(videoURL.lastPathComponent) || text.contains("TargetTimeRange") else { continue }
            if let parsed = parseMetadataJSON(data) { return parsed }
        }
        return nil
    }

    /// Parse draft metadata JSON. Handles both a structured dictionary
    /// (`SourceTimeRange` / `TargetTimeRange` objects with `Duration`,
    /// `StartTime`, `EndTime`) and flat text forms matched by regex.
    static func parseMetadataJSON(_ data: Data) -> DraftMetadata? {
        var result = DraftMetadata()
        var foundAnything = false

        if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
            if let source = json["SourceTimeRange"] as? [String: Any] {
                result.sourceStart = number(source["StartTime"])
                result.sourceEnd = number(source["EndTime"])
                result.sourceDuration = number(source["Duration"])
                foundAnything = true
            }
            if let target = json["TargetTimeRange"] as? [String: Any] {
                result.targetStart = number(target["StartTime"])
                result.targetEnd = number(target["EndTime"])
                result.targetDuration = number(target["Duration"])
                foundAnything = true
            }
            if let duration = number(json["Duration"]) {
                result.duration = duration
                foundAnything = true
            }
            if let start = number(json["StartTime"]) {
                result.startTime = start
                foundAnything = true
            }
            if let end = number(json["EndTime"]) {
                result.endTime = end
                foundAnything = true
            }
        }

        // Regex fallback for the compact text form, e.g.
        // "TargetTimeRange":{"Duration":12345 ...}
        let text = String(decoding: data, as: UTF8.self)
        if let duration = firstMatch(in: text, pattern: "\"TargetTimeRange\"\\s*:\\s*\\{[^}]*\"Duration\"\\s*:\\s*([0-9]+(?:\\.[0-9]+)?)") {
            result.targetDuration = duration
            foundAnything = true
        }
        if let duration = firstMatch(in: text, pattern: "\"SourceTimeRange\"\\s*:\\s*\\{[^}]*\"Duration\"\\s*:\\s*([0-9]+(?:\\.[0-9]+)?)") {
            result.sourceDuration = duration
            foundAnything = true
        }

        return foundAnything ? result : nil
    }

    private static func number(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private static func firstMatch(in text: String, pattern: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return Double(text[range])
    }
}
