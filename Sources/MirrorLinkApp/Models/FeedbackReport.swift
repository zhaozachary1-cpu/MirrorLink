import Foundation

struct FeedbackSessionSnapshot: Sendable {
    let state: String
    let quality: String
    let videoSize: String?
    let failure: String?
    init(state: String, quality: String, videoSize: String? = nil, failure: String? = nil) {
        self.state = state; self.quality = quality; self.videoSize = videoSize; self.failure = failure
    }
}

/// Deliberately excludes raw command output, logs, pairing data and device IDs.
/// The preview is exactly the diagnostics text exported into the feedback ZIP.
struct FeedbackReport: Sendable {
    let createdAt: Date
    let appVersion: String
    let build: String
    let device: AndroidDevice?
    let health: DeviceHealthReport?
    let session: FeedbackSessionSnapshot?

    init(appVersion: String, build: String, device: AndroidDevice?, health: DeviceHealthReport?,
         session: FeedbackSessionSnapshot?) {
        self.createdAt = Date(); self.appVersion = appVersion; self.build = build
        self.device = device; self.health = health; self.session = session
    }

    var preview: String {
        let secrets = [device?.serial, device?.hardwareSerial, device?.adbSocket, device?.sessionIdentity].compactMap { $0 }
        func clean(_ value: String?) -> String {
            FeedbackRedactor.redact(String((value ?? "—").prefix(256)), knownIdentifiers: secrets)
        }
        var lines = [L10n.tr("镜连反馈诊断（本地预览）"),
                     L10n.tr("生成时间：%@", L10n.formattedDate(createdAt)),
                     "MirrorLink: \(clean(appVersion)) / \(clean(build))",
                     "macOS: \(ProcessInfo.processInfo.operatingSystemVersion.majorVersion).\(ProcessInfo.processInfo.operatingSystemVersion.minorVersion).\(ProcessInfo.processInfo.operatingSystemVersion.patchVersion)",
                     L10n.tr("连接方式：%@", device.map { $0.isWireless ? "Wi-Fi" : "USB" } ?? "—"),
                     L10n.tr("设备状态：%@", clean(device?.state.rawValue)),
                     L10n.tr("型号：%@", clean(health?.model ?? device?.model)),
                     L10n.tr("Android 版本：%@", clean(health?.androidVersion)),
                     L10n.tr("手机显示尺寸：%@", clean(health?.screenSize)),
                     L10n.tr("连接检测：%@", health.map { $0.isReady ? L10n.tr("已就绪") : L10n.tr("未就绪") } ?? L10n.tr("未检测"))]
        if let session {
            lines += [L10n.tr("会话状态：%@", clean(session.state)), L10n.tr("画质设置：%@", clean(session.quality)),
                      L10n.tr("实际视频尺寸：%@", clean(session.videoSize)),
                      L10n.tr("会话错误：%@", session.failure == nil ? L10n.tr("无") : L10n.tr("有错误（不包含原始错误文本）"))]
        }
        lines += ["", L10n.tr("默认不包含屏幕画面、原始日志、序列号、网络地址、本机路径或配对凭据。"),
                  L10n.tr("附件仅来自用户本次明确选择的图片或视频；附件内容和元数据不会自动脱敏。"),
                  L10n.tr("此反馈包仅保存到本地，不会自动发送。")]
        return lines.joined(separator: "\n") + "\n"
    }
}

enum FeedbackRedactor {
    static func redact(_ value: String, knownIdentifiers: [String] = []) -> String {
        var text = value
        for identifier in knownIdentifiers.filter({ !$0.isEmpty }).sorted(by: { $0.count > $1.count }) {
            text = text.replacingOccurrences(of: identifier, with: "[redacted]", options: .caseInsensitive)
        }
        let patterns = [
            #"(?i)WIFI:[^\r\n]*"#,
            #"(?i)(?:password|passwd|secret|token|api[_-]?key|authorization|pairing[_ -]?(?:code|password)|ed25519|private[_ -]?key)\s*[:=]\s*[^\r\n]+"#,
            #"(?i)\b(?:sk-|gh[pousr]_|github_pat_)[A-Za-z0-9_-]+"#,
            #"(?i)-----BEGIN [^-]*PRIVATE KEY-----[\s\S]*"#,
            #"\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}(?::[0-9]+)?\b"#,
            #"(?i)(?:\b[0-9a-f]{1,4}:){2,7}[0-9a-f:]{0,39}(?:%[A-Za-z0-9]+)?"#,
            #"(?i)(?<![A-Za-z0-9])::[0-9a-f:]+(?:%[A-Za-z0-9]+)?"#,
            #"(?i)(?:[0-9a-f]{2}:){5}[0-9a-f]{2}"#,
            #"(?:file://)?/[^\r\n]*"#,
            #"(?i)\b(?:serial(?:no)?|device[_ -]?id|guid)\s*[:=]\s*[^\s,;]+"#,
            #"(?i)\b[A-Za-z0-9+/=_-]{32,}\b"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "[redacted]")
        }
        return text.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
    }
}
