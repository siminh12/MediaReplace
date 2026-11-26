// ContentView.swift
// MediaReplace — clean-room rewrite.
// Main screen: local notice bar, platform picker, draft list, empty state,
// folder picker entry, and the local-only export mode.

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var viewModel: MediaReplaceViewModel

    @State private var showingVideoPicker = false
    @State private var showingFolderPicker = false
    @State private var showingDeleteConfirmation = false
    @State private var draftPendingDeletion: DraftVideo?

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                noticeBar
                platformPicker
                actionRow
                draftList
            }
            .navigationBarTitle("媒体替换", displayMode: .inline)
            .navigationBarItems(trailing: refreshButton)
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .sheet(isPresented: $viewModel.showSegmentSheet) {
            FilePreviewSheet()
                .environmentObject(viewModel)
        }
        .sheet(isPresented: $showingVideoPicker) {
            VideoPicker { url in
                if let url = url {
                    viewModel.setReplacementVideo(url: url)
                }
            }
        }
        .sheet(isPresented: $showingFolderPicker) {
            FolderPicker { url in
                if let url = url {
                    viewModel.scanPickedFolder(url)
                }
            }
        }
        .sheet(isPresented: $viewModel.showShareSheet) {
            if let outputURL = viewModel.processedOutputURL {
                ShareSheet(urls: [outputURL])
            }
        }
        .alert(isPresented: $showingDeleteConfirmation) {
            Alert(
                title: Text("删除草稿视频"),
                message: Text("确定要删除“\(draftPendingDeletion?.fileName ?? "")”吗？此操作无法撤销。"),
                primaryButton: .destructive(Text("删除")) {
                    if let draft = draftPendingDeletion {
                        viewModel.deleteDraft(draft)
                    }
                    draftPendingDeletion = nil
                },
                secondaryButton: .cancel(Text("取消")) {
                    draftPendingDeletion = nil
                }
            )
        }
        .onAppear {
            if viewModel.drafts.isEmpty && viewModel.scanMessage == nil {
                viewModel.scanDrafts()
            }
        }
    }

    // MARK: - Notice bar (local text, scrolling marquee style)

    private var noticeBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "megaphone.fill")
                .foregroundColor(.accentColor)
            Text(viewModel.noticeText)
                .font(.footnote)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(UIColor.secondarySystemBackground))
    }

    // MARK: - Platform picker

    private var platformPicker: some View {
        Picker("平台", selection: $viewModel.selectedPlatform) {
            ForEach(PlatformChannel.allCases) { platform in
                Text(platform.displayName).tag(platform)
            }
        }
        .pickerStyle(SegmentedPickerStyle())
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Action row

    private var actionRow: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button(action: { viewModel.scanDrafts() }) {
                    Label("扫描草稿", systemImage: "magnifyingglass")
                }
                .buttonStyle(ActionButtonStyle())

                Button(action: { showingFolderPicker = true }) {
                    Label("选择草稿文件夹", systemImage: "folder")
                }
                .buttonStyle(ActionButtonStyle())
            }
            HStack(spacing: 8) {
                Button(action: { showingVideoPicker = true }) {
                    Label("选替换视频", systemImage: "film")
                }
                .buttonStyle(ActionButtonStyle())

                Button(action: { viewModel.exportLocally() }) {
                    Label("仅本地处理并导出", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(ActionButtonStyle())
                .disabled(viewModel.replacementVideoURL == nil || viewModel.isProcessingSegment)
            }
            if let info = viewModel.replacementInfo {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("已选：\(info.fileName)")
                        .font(.footnote)
                        .lineLimit(1)
                    Spacer()
                    Button("清除") { viewModel.clearReplacementVideo() }
                        .font(.footnote)
                }
                .padding(.horizontal, 12)
            }
            if viewModel.isProcessingSegment {
                ProgressView(value: viewModel.processingProgress)
                    .padding(.horizontal, 12)
            }
            if let message = viewModel.replaceState.message {
                Text(message)
                    .font(.footnote)
                    .foregroundColor(viewModel.replaceState == .succeeded ? .green : .red)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Draft list

    private var draftList: some View {
        Group {
            if viewModel.isScanning {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("正在扫描草稿…")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.selectedPlatformDrafts.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(viewModel.selectedPlatformDrafts) { draft in
                        DraftRow(draft: draft, onDelete: {
                            draftPendingDeletion = draft
                            showingDeleteConfirmation = true
                        })
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.selectedDraft = draft
                            viewModel.replaceState = .idle
                            viewModel.showSegmentSheet = true
                        }
                    }
                }
                .listStyle(PlainListStyle())
            }
        }
    }

    private var emptyState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("没有找到草稿")
                    .font(.headline)
                Text("这是正常情况：普通 App 无法读取其他 App 的容器。原工具能直接扫描，是因为它带有越狱 / 侧载专用的系统权限；本 App 不带这些权限，也不会索取。")
                    .font(.body)
                    .foregroundColor(.secondary)
                Text("可以这样用：")
                    .font(.headline)
                Text("1. 点“选择草稿文件夹”，在文件 App 里手动选一个已共享出来的草稿目录。\n2. 或者点“选替换视频”，再点“仅本地处理并导出”，不依赖草稿也能处理视频并保存到相册或文件。")
                    .font(.body)
                    .foregroundColor(.secondary)
                if let message = viewModel.scanMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
        }
    }

    private var refreshButton: some View {
        Button(action: { viewModel.refresh() }) {
            Image(systemName: "arrow.clockwise")
        }
        .disabled(viewModel.isScanning)
    }
}

// MARK: - Draft row

private struct DraftRow: View {
    let draft: DraftVideo
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "play.rectangle.fill")
                .font(.title2)
                .foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 4) {
                Text(draft.fileName)
                    .font(.body)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(draft.sizeDescription)
                    if let date = draft.modificationDate {
                        Text(date, style: .date)
                    }
                    if draft.metadata?.hasSegments == true {
                        Text("含分段")
                            .foregroundColor(.accentColor)
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            Spacer()
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Shared button style

private struct ActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color(UIColor.tertiarySystemBackground))
            .cornerRadius(10)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}
