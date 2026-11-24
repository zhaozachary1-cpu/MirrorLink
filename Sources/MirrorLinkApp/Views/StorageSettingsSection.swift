import AppKit
import SwiftUI

private typealias StorageViewState<Value> = SwiftUI.State<Value>

struct StorageSettingsSection: View {
    @EnvironmentObject private var tools: DeviceToolsStore
    @ObservedObject private var language = LanguageStore.shared
    @StorageViewState private var errorMessage: LocalizedMessage?

    var body: some View {
        let _ = language.selection
        Section(L10n.tr("文件保存位置")) {
            Text(tools.outputDirectory.path)
                .font(.caption.monospaced()).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(L10n.tr("选择文件夹…")) { chooseDirectory() }
                Button(L10n.tr("打开文件夹")) { openDirectory() }
            }
            if let errorMessage {
                Text(errorMessage.resolved).font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.title = L10n.tr("选择文件保存位置")
        panel.directoryURL = tools.outputDirectory
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try tools.setOutputDirectory(url)
            errorMessage = nil
        } catch {
            errorMessage = L10n.message("无法使用此文件夹：%@", error.localizedDescription)
        }
    }

    private func openDirectory() {
        do {
            try tools.setOutputDirectory(tools.outputDirectory)
            guard NSWorkspace.shared.open(tools.outputDirectory) else {
                errorMessage = L10n.message("无法打开保存文件夹，请检查文件夹是否可访问。")
                return
            }
            errorMessage = nil
        } catch {
            errorMessage = L10n.message("无法使用此文件夹：%@", error.localizedDescription)
        }
    }
}
