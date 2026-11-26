// FilePreviewSheet.swift
// MediaReplace — clean-room rewrite.
// Draft preview sheet: plays the draft video, lets the user pick the
// replacement video, toggles segment processing, and starts the replace.

import AVKit
import SwiftUI

struct FilePreviewSheet: View {
    @EnvironmentObject private var viewModel: MediaReplaceViewModel
    @Environment(\.presentationMode) private var presentationMode

    @State private var showingVideoPicker = false
    @State private var player: AVPlayer?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    draftInfo
                    previewPlayer
                    replacementSection
                    segmentSection
                    qualitySection
                    startButton
                    resultSection
                }
                .padding()
            }
            .navigationBarTitle("草稿预览", displayMode: .inline)
            .navigationBarItems(
                leading: Button("关闭") { presentationMode.wrappedValue.dismiss() },
                trailing: deleteButton
            )
        }
        .sheet(isPresented: $showingVideoPicker) {
            VideoPicker { url in
                if let url = url {
                    viewModel.setReplacementVideo(url: url)
                }
            }
        }
        .onAppear {
            if let draft = viewModel.selectedDraft {
                player = AVPlayer(url: draft.fileURL)
            }
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }

    // MARK: - Draft info

    private var draftInfo: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let draft = viewModel.selectedDraft {
                Text(draft.fileName)
                    .font(.headline)
                Text("\(draft.platform.displayName) · \(draft.sizeDescription)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(draft.fileURL.path)
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let metadata = draft.metadata {
                    metadataSummary(metadata)
                } else {
                    Text("未找到草稿元数据，将按整段处理。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                Text("未选择草稿")
                    .font(.headline)
            }
        }
    }

    private func metadataSummary(_ metadata: DraftMetadata) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let duration = metadata.duration ?? metadata.targetDuration {
                Text("草稿时长：\(formatted(seconds: duration))")
                    .font(.caption)
            }
            if metadata.hasSegments {
                Text("分段：\(metadata.segmentRanges.count) 段")
                    .font(.caption)
                    .foregroundColor(.accentColor)
                ForEach(Array(metadata.segmentRanges.enumerated()), id: \.offset) { index, range in
                    Text("第 \(index + 1) 段：\(formatted(seconds: range.start)) – \(formatted(seconds: range.end))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func formatted(seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: - Preview player

    private var previewPlayer: some View {
        Group {
            if let player = player {
                VideoPlayer(player: player)
                    .frame(height: 240)
                    .cornerRadius(12)
                    .onAppear { player.play() }
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(UIColor.secondarySystemBackground))
                    .frame(height: 240)
                    .overlay(Text("无法预览该视频").foregroundColor(.secondary))
            }
        }
    }

    // MARK: - Replacement video

    private var replacementSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("替换视频")
                .font(.headline)
            Button(action: { showingVideoPicker = true }) {
                Label("从相册选择视频", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color(UIColor.tertiarySystemBackground))
                    .cornerRadius(10)
            }
            if let info = viewModel.replacementInfo {
                VStack(alignment: .leading, spacing: 4) {
                    Text(info.fileName)
                        .font(.subheadline)
                        .lineLimit(1)
                    if let duration = info.durationSeconds {
                        Text("时长：\(formatted(seconds: duration))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Segment & quality

    private var segmentSection: some View {
        Toggle("按草稿时间范围分段处理", isOn: $viewModel.enableSegmentProcess)
            .toggleStyle(SwitchToggleStyle())
    }

    private var qualitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("导出画质")
                .font(.headline)
            Picker("导出画质", selection: $viewModel.exportQuality) {
                ForEach(ExportQuality.allCases, id: \.self) { quality in
                    Text(quality.displayName).tag(quality)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
        }
    }

    // MARK: - Start & result

    private var startButton: some View {
        VStack(spacing: 8) {
            Button(action: { viewModel.startReplace() }) {
                Text(viewModel.isProcessingSegment ? "处理中…" : "开始替换")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(viewModel.replacementVideoURL == nil ? Color.gray : Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .disabled(viewModel.replacementVideoURL == nil || viewModel.isProcessingSegment)
            if viewModel.isProcessingSegment {
                ProgressView(value: viewModel.processingProgress)
                Text("正在处理视频，请稍候…")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text("替换前会把原草稿视频备份为同名 .bak 文件。")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var resultSection: some View {
        Group {
            switch viewModel.replaceState {
            case .succeeded:
                Label("替换成功", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
            case .failed(let reason):
                Label("替换失败：\(reason)", systemImage: "xmark.circle.fill")
                    .foregroundColor(.red)
            case .idle, .processing:
                EmptyView()
            }
        }
    }

    private var deleteButton: some View {
        Button(action: {
            if let draft = viewModel.selectedDraft {
                viewModel.deleteDraft(draft)
                presentationMode.wrappedValue.dismiss()
            }
        }) {
            Image(systemName: "trash")
                .foregroundColor(.red)
        }
        .disabled(viewModel.selectedDraft == nil)
    }
}
