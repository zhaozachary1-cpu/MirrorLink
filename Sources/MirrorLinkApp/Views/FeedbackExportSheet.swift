import AppKit
import SwiftUI
import UniformTypeIdentifiers

private typealias FeedbackViewState<Value> = SwiftUI.State<Value>

struct FeedbackExportSheet: View {
    let device: AndroidDevice
    @ObservedObject var store: MirrorSessionStore
    @ObservedObject private var language = LanguageStore.shared
    @EnvironmentObject private var tools: DeviceToolsStore
    @Environment(\.dismiss) private var dismiss
    @FeedbackViewState private var attachments: [URL] = []
    @FeedbackViewState private var report: FeedbackReport?

    var body: some View {
        let _ = language.selection
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(L10n.tr("导出问题反馈")).font(.title2.weight(.semibold))
                Spacer()
                Button(L10n.tr("关闭")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(tools.feedbackIsBusy)
            }
            Text(L10n.tr("先检查下方内容，再保存到本地 ZIP 文件。镜连不会自动上传或发送反馈。"))
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            GroupBox(L10n.tr("诊断内容预览")) {
                ScrollView {
                    Text(report?.preview ?? "")
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }.frame(minHeight: 190, maxHeight: .infinity)
            }
            Text(L10n.tr("诊断内容已限制为必要的版本和状态信息，不收集原始日志、配对码或手机文件。"))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            GroupBox(L10n.tr("可选附件")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.tr("默认不附加截图或录屏。附件可能包含屏幕上的私人内容，请自行检查；上方文本预览不包含附件画面。"))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(L10n.tr("反馈附件仅支持普通图片或视频文件，最多 8 个，每个不超过 512 MB，总计不超过 1 GB；不支持符号链接。"))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !attachments.isEmpty {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(attachments, id: \.self) { url in
                                    HStack {
                                        Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                                        Spacer()
                                        Button { attachments.removeAll { $0 == url } } label: {
                                            Image(systemName: "xmark.circle")
                                        }
                                        .buttonStyle(.borderless)
                                        .accessibilityLabel(L10n.tr("移除附件 %@", url.lastPathComponent))
                                        .disabled(tools.feedbackIsBusy)
                                    }
                                }
                            }
                        }.frame(maxHeight: 100)
                    }
                    Button(L10n.tr("选择截图或录屏…")) { chooseAttachments() }
                        .disabled(tools.feedbackIsBusy)
                }.padding(4)
            }
            if let status = tools.feedbackStatus {
                Text(status).font(.caption).fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(tools.feedbackIsError ? Color.red : Color.secondary)
            }
            HStack {
                if tools.feedbackIsBusy {
                    ProgressView().controlSize(.small)
                    Button(L10n.tr("取消导出")) { tools.cancelFeedback() }
                } else if let url = tools.lastFeedbackURL {
                    Button(L10n.tr("显示已导出的反馈文件")) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }
                Spacer()
                Button(L10n.tr("保存反馈 ZIP…")) { export() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(report == nil || tools.feedbackIsBusy)
            }
        }
        .padding(22)
        .frame(width: 660, height: 720)
        .onAppear { refreshPreview() }
        .onChange(of: language.selection) { _ in refreshPreview() }
        .interactiveDismissDisabled(tools.feedbackIsBusy)
    }

    private func refreshPreview() {
        let state = store.sessionState(for: device)
        let video = store.videoStatus(for: device.id)
        let failure: String?
        if case let .failed(message) = state { failure = message } else { failure = nil }
        report = FeedbackReport(
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            device: device,
            health: tools.healthReport(for: device.id),
            session: FeedbackSessionSnapshot(
                state: state.title,
                quality: (video?.profile ?? store.preferences(for: device).qualityProfile ?? store.qualityProfile).title,
                videoSize: video?.resolution?.displayText,
                failure: failure
            )
        )
    }

    private func chooseAttachments() {
        let panel = NSOpenPanel()
        panel.title = L10n.tr("选择反馈附件")
        panel.directoryURL = tools.outputDirectory
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = ["png", "jpg", "jpeg", "heic", "mov", "mp4", "mkv"].compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK else { return }
        for url in panel.urls where !attachments.contains(url) { attachments.append(url) }
    }

    private func export() {
        guard let report else { return }
        let panel = NSSavePanel()
        panel.title = L10n.tr("保存反馈文件")
        panel.directoryURL = tools.outputDirectory
        panel.nameFieldStringValue = "MirrorLink-Feedback-\(Int(Date().timeIntervalSince1970)).zip"
        panel.allowedContentTypes = [.zip]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        tools.exportFeedback(report, attachments: attachments, to: destination)
    }
}
