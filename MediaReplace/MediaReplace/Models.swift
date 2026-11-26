// Models.swift
// MediaReplace — clean-room rewrite.
// Data models for local draft-video replacement. No networking, no activation.

import Foundation

/// A short-video platform whose draft folders we know how to look for.
/// The names are factual labels for the user's own installed apps.
enum PlatformChannel: String, CaseIterable, Identifiable {
    case douyin = "douyin"
    case kuaishou = "kuaishou"
    case xiaohongshu = "xiaohongshu"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .douyin: return "抖音 / TikTok"
        case .kuaishou: return "快手"
        case .xiaohongshu: return "小红书"
        }
    }

    /// App bundle identifiers that own the draft containers.
    var bundleIdentifiers: [String] {
        switch self {
        case .douyin:
            return ["com.ss.iphone.ugc.Aweme", "AwemeInhouse", "AwemeLite"]
        case .kuaishou:
            return ["com.kuaishou.gifshow"]
        case .xiaohongshu:
            return ["com.xingin.discover"]
        }
    }

    /// Draft folders relative to an app container root.
    var relativeDraftPaths: [String] {
        switch self {
        case .douyin:
            return [
                "Documents/drafts",
                "Documents/aweme_drafts",
                "Documents/AwemeDrafts",
                "Library/Application Support/drafts",
                "Library/Caches/drafts"
            ]
        case .kuaishou:
            return [
                "Documents/Gifshow/Drafts",
                "Library/Application Support/gifs"
            ]
        case .xiaohongshu:
            return [
                "Documents/Post/Drafts",
                "Documents/Post/drafts",
                "Library/Application Support/Post/Drafts"
            ]
        }
    }
}

/// One draft video found on disk, plus the metadata that describes it.
struct DraftVideo: Identifiable, Hashable {
    let id: UUID
    let platform: PlatformChannel
    let fileURL: URL
    let fileName: String
    let fileSize: Int64
    let modificationDate: Date?
    let metadata: DraftMetadata?

    var displayName: String { fileName }

    var sizeDescription: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    static func == (lhs: DraftVideo, rhs: DraftVideo) -> Bool {
        lhs.fileURL == rhs.fileURL
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(fileURL)
    }
}

/// Time ranges and timing fields read out of a draft's JSON metadata file.
/// Times are in seconds.
struct DraftMetadata {
    var sourceStart: Double?
    var sourceEnd: Double?
    var sourceDuration: Double?
    var targetStart: Double?
    var targetEnd: Double?
    var targetDuration: Double?
    var startTime: Double?
    var endTime: Double?
    var duration: Double?

    /// The ranges the replacement video should be cut to, if any.
    var segmentRanges: [(start: Double, end: Double)] {
        var ranges: [(Double, Double)] = []
        if let s = targetStart, let e = targetEnd, e > s {
            ranges.append((s, e))
        } else if let d = targetDuration, d > 0 {
            ranges.append((0, d))
        }
        return ranges
    }

    var hasSegments: Bool { !segmentRanges.isEmpty }
}

/// Basic info about a media file chosen by the user.
struct MediaFileInfo {
    let url: URL
    let fileName: String
    let durationSeconds: Double?
    let fileSize: Int64?
}

/// Overall outcome of a replace operation.
enum ReplaceState: Equatable {
    case idle
    case processing
    case succeeded
    case failed(String)

    var message: String? {
        switch self {
        case .idle, .processing: return nil
        case .succeeded: return "替换成功"
        case .failed(let reason): return reason
        }
    }
}

/// Outcome of deleting a draft video.
enum DeleteState: Equatable {
    case idle
    case succeeded
    case failed(String)
}

/// Errors raised while processing video.
enum ProcessError: LocalizedError {
    case assetNotReadable
    case noVideoTrack
    case exportSessionUnavailable
    case exportFailed(String)
    case exportCancelled
    case invalidTimeRange
    case outputWriteFailed(String)

    var errorDescription: String? {
        switch self {
        case .assetNotReadable: return "无法读取源视频"
        case .noVideoTrack: return "源视频中没有视频轨道"
        case .exportSessionUnavailable: return "无法创建导出会话"
        case .exportFailed(let detail): return "导出失败：\(detail)"
        case .exportCancelled: return "导出已取消"
        case .invalidTimeRange: return "时间范围无效"
        case .outputWriteFailed(let detail): return "写入输出文件失败：\(detail)"
        }
    }
}

/// Errors raised while replacing a draft file.
enum ReplaceError: LocalizedError {
    case backupFailed(String)
    case copyFailed(String)
    case targetMissing
    case deleteFailed(String)

    var errorDescription: String? {
        switch self {
        case .backupFailed(let detail): return "备份原文件失败：\(detail)"
        case .copyFailed(let detail): return "写入替换文件失败：\(detail)"
        case .targetMissing: return "目标草稿文件不存在"
        case .deleteFailed(let detail): return "删除草稿失败：\(detail)"
        }
    }
}
