import AppKit
import SwiftUI

private typealias ToolViewState<Value> = SwiftUI.State<Value>

struct DeviceToolsView: View {
    @ObservedObject private var language = LanguageStore.shared
    @ObservedObject var store: MirrorSessionStore
    @EnvironmentObject private var tools: DeviceToolsStore
    let device: AndroidDevice
    @ToolViewState private var expanded = false
    @ToolViewState private var showsFeedback = false
    @ToolViewState private var localMessage: LocalizedMessage?

    private var ready: Bool { store.connectedDevice(for: device.id)?.state == .ready }
    private var actionDevice: AndroidDevice { store.connectedDevice(for: device.id) ?? device }
    private var busy: Bool { tools.isBusy(for: device.id) }
    private var presentation: Bool {
        store.isPresentationMode(for: device)
    }

    var body: some View {
        let _ = language.selection
        VStack(alignment: .leading, spacing: 10) {
            if presentation {
                Text(L10n.tr("演示模式已禁用手机导航与写入操作。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 12) {
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
                Label(L10n.tr("自检与反馈"), systemImage: "wrench.and.screwdriver")
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
        .sheet(isPresented: $showsFeedback) {
            FeedbackExportSheet(device: device, store: store).environmentObject(tools)
        }
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
