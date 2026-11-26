// ReplaceEngine.swift
// MediaReplace — clean-room rewrite.
// Writes a processed video over a draft file, after backing the original
// up as a same-name `.bak` file. Local file operations only.

import Foundation

/// Performs the actual file replacement, backup and deletion.
final class ReplaceEngine {

    /// Back up `targetURL` to `targetURL` + ".bak", then overwrite the
    /// target with the processed video at `processedURL`.
    static func replaceDraft(
        targetURL: URL,
        withProcessedVideo processedURL: URL
    ) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: targetURL.path) else {
            throw ReplaceError.targetMissing
        }

        // 1. Back up the original draft video.
        let backupURL = targetURL.appendingPathExtension("bak")
        do {
            if fileManager.fileExists(atPath: backupURL.path) {
                try fileManager.removeItem(at: backupURL)
            }
            try fileManager.copyItem(at: targetURL, to: backupURL)
        } catch {
            throw ReplaceError.backupFailed(error.localizedDescription)
        }

        // 2. Overwrite the draft with the processed video.
        do {
            try fileManager.removeItem(at: targetURL)
            try fileManager.copyItem(at: processedURL, to: targetURL)
        } catch {
            // Try to restore the backup so the draft is not left broken.
            try? fileManager.removeItem(at: targetURL)
            try? fileManager.copyItem(at: backupURL, to: targetURL)
            throw ReplaceError.copyFailed(error.localizedDescription)
        }
    }

    /// Delete a draft video file.
    static func deleteDraft(at url: URL) throws {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            throw ReplaceError.deleteFailed(error.localizedDescription)
        }
    }

    /// Remove a temporary processed file once it is no longer needed.
    static func removeTemporaryFile(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
