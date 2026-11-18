import AppKit
import SwiftUI
import UniformTypeIdentifiers

private typealias ToolViewState<Value> = SwiftUI.State<Value>

struct DeviceToolsView: View {
    @ObservedObject private var language = LanguageStore.shared
    @ObservedObject var store: MirrorSessionStore
    @EnvironmentObject private var tools: DeviceToolsStore
    let device: AndroidDevice
    @ToolViewState private var expanded = false
    @ToolViewState private var confirmsRecording = false
    @ToolViewState private var confirmsStopRecording = false
    @ToolViewState private var pendingAPK: URL?
    @ToolViewState private var confirmsAPK = false
    @ToolViewState private var showsFeedback = false
    @ToolViewState private var localMessage: LocalizedMessage?

    private var ready: Bool { store.connectedDevice(for: device.id)?.state == .ready }
    private var actionDevice: AndroidDevice { store.connectedDevice(for: device.id) ?? device }
    private var busy: Bool { tools.isBusy(for: device.id) }
    private var presentation: Bool {
        store.isPresentationMode(for: device)
    }
    private var navigationDisabled: Bool { !ready || busy || presentation }
    private var recordingDisabled: Bool {
        (!ready && !store.isRecording(for: device.id))
            || store.isRestartPending(for: device.id) || store.sessionState(for: device) == .stopping
    }

    var body: some View {
        let _ = language.selection
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button { tools.home(for: actionDevice) } label: {
                    Label(L10n.tr("返回桌面"), systemImage: "house")
                }
                .disabled(navigationDisabled)
                .help(L10n.tr("向这台手机发送 Home 操作"))
                Button { tools.openAppDrawer(for: actionDevice) } label: {
                    Label(L10n.tr("应用列表"), systemImage: "square.grid.3x3")
                }
                .disabled(navigationDisabled)
                .help(L10n.tr("请求手机启动器显示全部应用；部分启动器不支持。"))
                Spacer(minLength: 0)
            }
            .buttonStyle(.bordered)
            if presentation {
                Text(L10n.tr("演示模式已禁用手机导航与写入操作。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Button { tools.captureScreenshot(for: actionDevice) } label: {
                            Label(L10n.tr("保存截图"), systemImage: "camera")
                        }.disabled(!ready || busy)
                        if store.isRecording(for: device.id) {
                            Button { confirmsStopRecording = true } label: {
                                Label(L10n.tr("结束录屏"), systemImage: "stop.circle.fill")
                            }.tint(.red).disabled(recordingDisabled)
                        } else {
                            Button { confirmsRecording = true } label: {
                                Label(L10n.tr("开始录屏…"), systemImage: "record.circle")
                            }.disabled(recordingDisabled)
                        }
                        Spacer(minLength: 0)
                    }
                    if let screenshot = tools.lastScreenshotURL(for: device.id) {
                        HStack {
                            Text(L10n.tr("最近截图")).font(.caption).foregroundStyle(.secondary)
                            Button(L10n.tr("复制截图")) { copyScreenshot(screenshot) }
                            Button(L10n.tr("在访达中显示")) { NSWorkspace.shared.activateFileViewerSelecting([screenshot]) }
                        }
                    }
                    if let recording = store.lastRecordingURL(for: device.id) {
                        HStack {
                            Text(L10n.tr("已保存的录屏")).font(.caption).foregroundStyle(.secondary)
                            Button(L10n.tr("在访达中显示")) { NSWorkspace.shared.activateFileViewerSelecting([recording]) }
                        }
                    }
                    if let message = store.recordingMessage(for: device.id) {
                        Text(message).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Divider()
                    HStack(spacing: 8) {
                        Button { chooseFile() } label: {
                            Label(L10n.tr("发送文件…"), systemImage: "paperplane")
                        }.disabled(!ready || busy || presentation)
                        Button { chooseAPK() } label: {
                            Label(L10n.tr("安装 APK…"), systemImage: "shippingbox")
                        }.disabled(!ready || busy || presentation)
                        Spacer(minLength: 0)
                    }
                    Text(L10n.tr("文件发送到手机 Download 文件夹；APK 必须通过“安装 APK”单独确认。"))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(L10n.tr("尝试上滑打开应用列表")) { tools.swipeUpForDrawer(for: actionDevice) }
                        .disabled(navigationDisabled)
                    Text(L10n.tr("如果应用列表指令无效果，可先返回桌面，再尝试上滑。部分桌面没有独立应用抽屉，两种方式都可能无效果，可在手机桌面查找应用。镜连不会更改手机桌面设置，结果以实际画面为准。"))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Divider()
                    HStack(spacing: 8) {
                        Button { tools.runHealthCheck(for: actionDevice) } label: {
                            Label(L10n.tr("检查连接与环境"), systemImage: "stethoscope")
                        }.disabled(busy || !store.toolchainAvailable)
                        Button { showsFeedback = true } label: {
                            Label(L10n.tr("导出问题反馈…"), systemImage: "square.and.arrow.up")
                        }
                        Spacer(minLength: 0)
                    }
                    if let report = tools.healthReport(for: device.id) {
                        DeviceHealthView(report: report)
                    }
                }
                .buttonStyle(.bordered)
                .padding(.top, 10)
            } label: {
                Label(L10n.tr("截图、录屏与更多工具"), systemImage: "wrench.and.screwdriver")
                    .font(.callout)
            }
            if busy {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(tools.status(for: device.id) ?? L10n.tr("正在处理…"))
                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button(L10n.tr("取消操作")) { tools.cancel(for: device.id) }
                }
            } else if let status = tools.status(for: device.id) {
                Text(status).font(.caption)
                    .foregroundStyle(tools.isError(for: device.id) ? Color.red : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let localMessage {
                Text(localMessage.resolved).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .confirmationDialog(L10n.tr("开始这台设备的录屏？"), isPresented: $confirmsRecording, titleVisibility: .visible) {
            Button(L10n.tr("选择保存位置并录屏…")) { chooseRecordingDestination() }
            Button(L10n.tr("取消"), role: .cancel) {}
        } message: {
            Text(L10n.tr("将启动或重新启动这台设备的投屏并开始录制，当前画面会短暂中断；其他手机不受影响。录屏可能包含手机上的私人内容。"))
        }
        .confirmationDialog(L10n.tr("结束录屏并继续投屏？"), isPresented: $confirmsStopRecording, titleVisibility: .visible) {
            Button(L10n.tr("保存并继续投屏")) { store.stopRecording(for: device.id) }
            Button(L10n.tr("取消"), role: .cancel) {}
        } message: {
            Text(L10n.tr("镜连将保存本次录屏，并重新打开这台设备的普通投屏窗口；其他手机不受影响。"))
        }
        .confirmationDialog(L10n.tr("确认安装所选 APK？"), isPresented: $confirmsAPK, titleVisibility: .visible) {
            Button(L10n.tr("安装到这台设备")) {
                if let pendingAPK, !presentation { tools.installAPK(pendingAPK, to: actionDevice, confirmed: true) }
                pendingAPK = nil
            }
            Button(L10n.tr("取消"), role: .cancel) { pendingAPK = nil }
        } message: {
            Text(L10n.tr("将 %@ 安装到 %@。请确认文件来源；不会覆盖已安装的应用，存在冲突时安装会失败。", pendingAPK?.lastPathComponent ?? "", store.displayName(for: device)))
        }
        .sheet(isPresented: $showsFeedback) {
            FeedbackExportSheet(device: device, store: store).environmentObject(tools)
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.title = L10n.tr("选择要发送的文件")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard url.pathExtension.lowercased() != "apk" else {
            localMessage = L10n.message("要安装 APK，请使用“安装 APK”按钮并确认安装。")
            return
        }
        localMessage = nil
        guard !presentation else { return }
        tools.sendFile(url, to: actionDevice)
    }

    private func chooseAPK() {
        let panel = NSOpenPanel()
        panel.title = L10n.tr("选择要安装的 APK")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if let apkType = UTType(filenameExtension: "apk") { panel.allowedContentTypes = [apkType] }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard url.pathExtension.lowercased() == "apk" else {
            localMessage = L10n.message("请选择扩展名为 .apk 的安装文件。")
            return
        }
        pendingAPK = url
        confirmsAPK = true
    }

    private func chooseRecordingDestination() {
        let panel = NSSavePanel()
        panel.title = L10n.tr("保存录屏")
        panel.directoryURL = tools.outputDirectory
        panel.nameFieldStringValue = "MirrorLink-Recording-\(Int(Date().timeIntervalSince1970)).mp4"
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.startRecording(for: device.id, to: url)
    }

    private func copyScreenshot(_ url: URL) {
        guard let image = NSImage(contentsOf: url) else {
            localMessage = L10n.message("截图文件无法读取，请重新截图。")
            return
        }
        NSPasteboard.general.clearContents()
        let copied = NSPasteboard.general.writeObjects([image])
        localMessage = copied ? L10n.message("截图已复制到剪贴板。") : L10n.message("无法复制截图，请重试。")
    }
}

private struct DeviceHealthView: View {
    @ObservedObject private var language = LanguageStore.shared
    let report: DeviceHealthReport

    var body: some View {
        let _ = language.selection
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 10) {
                Text(report.checkedAt, style: .time).font(.caption).foregroundStyle(.secondary)
                ForEach(report.items) { item in
                    VStack(alignment: .leading, spacing: 3) {
                        Label(item.title, systemImage: symbol(for: item.severity))
                            .font(.callout.weight(.medium)).foregroundStyle(tint(for: item.severity))
                        Text(item.detail).font(.caption).foregroundStyle(.secondary)
                        if let suggestion = item.suggestion {
                            Text(suggestion).font(.caption)
                        }
                    }.fixedSize(horizontal: false, vertical: true)
                }
            }.padding(.top, 8)
        } label: {
            Label(L10n.tr("查看最近一次检查结果"), systemImage: report.isReady ? "checkmark.circle" : "exclamationmark.triangle")
        }
    }

    private func symbol(for severity: DeviceHealthSeverity) -> String {
        switch severity {
        case .success: return "checkmark.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.circle"
        case .info: return "info.circle"
        }
    }

    private func tint(for severity: DeviceHealthSeverity) -> Color {
        switch severity {
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        case .info: return .secondary
        }
    }
}
