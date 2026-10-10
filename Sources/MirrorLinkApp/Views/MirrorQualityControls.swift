import SwiftUI

/// Edits the preference for the next session, never the snapshot of a running one.
struct MirrorQualityControls: View {
    @Binding var profile: MirrorQualityProfile
    var showsAdditionalGuidance = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("画质", selection: $profile) {
                ForEach(MirrorQualityProfile.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 300, alignment: .leading)
            .accessibilityHint("选择下次开始或重新投屏时使用的画质")

            Text(profile.configurationSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(profile.detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("更改在下次开始时生效。正在投屏的设备可点击“重新投屏”应用新画质；主窗口的设备列表显示本次投屏的实际配置。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if showsAdditionalGuidance {
                Text("超清保留手机原生细节，不将低分辨率画面放大冒充 4K。长时间查看文字建议使用“原生超清”；多台设备会共同占用编码、网络与 Mac 解码资源。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("无线投屏使用 80 ms 视频缓冲平滑短时抖动，会增加少量延迟。网络持续不足或手机过热时仍可能卡顿，可优先改用 USB 连接。目标码率与帧率上限不代表实测值。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
