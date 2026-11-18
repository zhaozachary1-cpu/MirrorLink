import SwiftUI

private typealias PreferenceState<Value> = SwiftUI.State<Value>

struct DevicePreferencesSheet: View {
    @ObservedObject private var language = LanguageStore.shared
    @ObservedObject var store: MirrorSessionStore
    @Environment(\.dismiss) private var dismiss
    @PreferenceState private var draft: DevicePreferences
    @PreferenceState private var confirmsForget = false
    private let device: AndroidDevice?
    private let knownID: String?
    private let originalName: String

    init(store: MirrorSessionStore, device: AndroidDevice) {
        self.store = store
        self.device = device
        knownID = DevicePreferences.identity(for: device) ?? store.knownDevices.first(where: { $0.id == "hardware:\(device.hardwareSerial ?? device.serial)" })?.id
        originalName = device.model?.replacingOccurrences(of: "_", with: " ") ?? L10n.tr("Android 手机")
        _draft = PreferenceState(initialValue: store.preferences(for: device))
    }

    init(store: MirrorSessionStore, knownDevice: KnownDevice) {
        self.store = store
        device = nil
        knownID = knownDevice.id
        originalName = knownDevice.model
        _draft = PreferenceState(initialValue: knownDevice.preferences)
    }

    private var nicknameError: String? {
        if draft.nickname.count > 48 { return L10n.tr("昵称最多 48 个字符。") }
        if draft.nickname.rangeOfCharacter(from: .controlCharacters) != nil {
            return L10n.tr("昵称不能包含换行或控制字符。")
        }
        return nil
    }

    var body: some View {
        let _ = language.selection
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.tr("设备设置")).font(.title2.weight(.semibold))
                    Text(originalName).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                Button(L10n.tr("取消")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L10n.tr("保存")) { save(); dismiss() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(nicknameError != nil)
            }.padding(20)
            Divider()
            Form {
                Section(L10n.tr("识别设备")) {
                    TextField(L10n.tr("设备昵称"), text: $draft.nickname, prompt: Text(originalName))
                        .textFieldStyle(.roundedBorder)
                    if let nicknameError {
                        Text(nicknameError).font(.caption).foregroundStyle(.red)
                    }
                    Toggle(L10n.tr("收藏为常用设备"), isOn: $draft.favorite)
                        .disabled(knownID == nil)
                    Text(L10n.tr("收藏后，设备断开时仍会显示在常用设备列表。"))
                        .font(.caption).foregroundStyle(.secondary)
                    if knownID == nil {
                        Text(L10n.tr("尚未确认设备身份，当前偏好仅用于本次连接；收藏与自动恢复暂不可用。"))
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
                Section(L10n.tr("画质与声音")) {
                    Picker(L10n.tr("这台设备的画质"), selection: $draft.qualityProfile) {
                        Text(L10n.tr("跟随全局设置")).tag(Optional<MirrorQualityProfile>.none)
                        ForEach(MirrorQualityProfile.allCases) { profile in
                            Text(profile.title).tag(Optional(profile))
                        }
                    }
                    Toggle(L10n.tr("转发手机声音"), isOn: $draft.audioEnabled)
                    Text(L10n.tr("声音转发取决于 Android 版本、应用限制及手机支持。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section(L10n.tr("连接与演示")) {
                    Toggle(L10n.tr("意外断开后自动恢复"), isOn: $draft.autoReconnect)
                        .disabled(knownID == nil)
                    Text(L10n.tr("仅恢复这台已授权设备；手动停止后不会自动重开。可在设备卡片取消恢复。"))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Toggle(L10n.tr("演示模式"), isOn: $draft.presentationMode)
                    Text(L10n.tr("只读投屏、关闭剪贴板同步，并在界面和窗口标题隐藏设备序列号。截图和反馈附件仍可能包含屏幕上的私人内容。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section(L10n.tr("窗口")) {
                    Toggle(L10n.tr("启动时全屏"), isOn: $draft.fullscreen)
                    Toggle(L10n.tr("窗口始终置顶"), isOn: $draft.alwaysOnTop)
                    Text(L10n.tr("画质、声音、演示和窗口设置在下次启动或重新投屏时生效。保存不会中断当前投屏。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if knownID != nil { Section {
                    Button(device == nil ? L10n.tr("忘记此设备的设置…") : L10n.tr("重置设备偏好…"), role: .destructive) { confirmsForget = true }
                        .buttonStyle(.borderless)
                } }
            }
            .formStyle(.grouped)
        }
        .frame(width: 600, height: 700)
        .confirmationDialog(device == nil ? L10n.tr("忘记此设备的设置？") : L10n.tr("重置这台设备的偏好？"), isPresented: $confirmsForget, titleVisibility: .visible) {
            Button(L10n.tr("忘记设置"), role: .destructive) {
                if let knownID { store.forgetKnownDevice(knownID) }
                dismiss()
            }
            Button(L10n.tr("取消"), role: .cancel) {}
        } message: {
            Text(L10n.tr("仅清除镜连保存的昵称、收藏和设备偏好，不会撤销手机上的 ADB 配对授权，也不会删除手机数据。"))
            if device != nil {
                Text(L10n.tr("连接中的设备仍会出现在设备列表，并恢复默认偏好。"))
            }
        }
    }

    private func save() {
        draft.nickname = draft.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        if let device { store.updatePreferences(for: device, preferences: draft) }
        else if let knownID { store.updatePreferences(forKnownDeviceID: knownID, preferences: draft) }
    }
}
