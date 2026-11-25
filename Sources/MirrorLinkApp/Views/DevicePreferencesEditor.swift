import SwiftUI

private typealias PreferenceState<Value> = SwiftUI.State<Value>

struct DevicePreferencesEditor: View {
    @ObservedObject private var language = LanguageStore.shared
    @ObservedObject var store: MirrorSessionStore
    private let onFinish: () -> Void
    @PreferenceState private var draft: DevicePreferences
    @PreferenceState private var confirmsForget = false
    private let device: AndroidDevice?
    private let knownID: String?
    private let originalName: String

    init(store: MirrorSessionStore, device: AndroidDevice, onFinish: @escaping () -> Void) {
        self.store = store
        self.onFinish = onFinish
        self.device = device
        knownID = DevicePreferences.identity(for: device) ?? store.knownDevices.first(where: { $0.id == "hardware:\(device.hardwareSerial ?? device.serial)" })?.id
        originalName = device.displayName == device.serial ? L10n.tr("Android 手机") : device.displayName
        _draft = PreferenceState(initialValue: store.preferences(for: device))
    }

    init(store: MirrorSessionStore, knownDevice: KnownDevice, onFinish: @escaping () -> Void) {
        self.store = store
        self.onFinish = onFinish
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.tr("设备设置")).font(.headline)
                }
                Spacer()
                Button(L10n.tr("取消")) { onFinish() }
                Button(L10n.tr("保存")) { save(); onFinish() }
                    .buttonStyle(.borderedProminent)
                    .disabled(nicknameError != nil)
            }
            VStack(alignment: .leading, spacing: 12) {
                Section(L10n.tr("识别设备")) {
                    TextField(L10n.tr("设备昵称"), text: $draft.nickname, prompt: Text(originalName))
                        .textFieldStyle(.roundedBorder)
                    if let nicknameError {
                        Text(nicknameError).font(.caption).foregroundStyle(.red)
                    }
                    Toggle(L10n.tr("收藏为常用设备"), isOn: $draft.favorite)
                        .disabled(knownID == nil)
                    if knownID == nil {
                        Text(L10n.tr("未确认手机身份，偏好仅对本次连接生效。"))
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
                }
                Section(L10n.tr("连接与演示")) {
                    Toggle(L10n.tr("意外断开后自动恢复"), isOn: $draft.autoReconnect)
                        .disabled(knownID == nil)
                    Toggle(L10n.tr("演示模式"), isOn: $draft.presentationMode)
                    Text(L10n.tr("禁止控制和剪贴板同步，隐藏设备标识；画面仍可能含隐私。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section(L10n.tr("窗口")) {
                    Toggle(L10n.tr("启动时全屏"), isOn: $draft.fullscreen)
                    Toggle(L10n.tr("窗口始终置顶"), isOn: $draft.alwaysOnTop)
                    Text(L10n.tr("下次投屏时生效。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if knownID != nil { Section {
                    Button(device == nil ? L10n.tr("忘记此设备的设置…") : L10n.tr("重置设备偏好…"), role: .destructive) { confirmsForget = true }
                        .buttonStyle(.borderless)
                } }
            }
            if confirmsForget {
                Text(L10n.tr("仅清除昵称和设备偏好，手机授权与数据保留。"))
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(L10n.tr("取消")) { confirmsForget = false }
                    Button(L10n.tr("忘记设置"), role: .destructive) {
                        if let knownID { store.forgetKnownDevice(knownID) }
                        onFinish()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .buttonStyle(.bordered)
    }

    private func save() {
        draft.nickname = draft.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        if let device { store.updatePreferences(for: device, preferences: draft) }
        else if let knownID { store.updatePreferences(forKnownDeviceID: knownID, preferences: draft) }
    }
}
