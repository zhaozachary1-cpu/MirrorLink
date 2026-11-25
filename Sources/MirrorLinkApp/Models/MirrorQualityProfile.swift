import Foundation

/// Encoding requests, not a promise of measured bitrate/FPS or 4K source detail.
enum MirrorQualityProfile: String, CaseIterable, Identifiable {
    case nativeClarity
    case nativeSmooth
    case compatibility

    static let preferenceKey = "MirrorLinkVideoQualityProfile"
    static func restored(from value: String?) -> Self {
        value.flatMap(Self.init(rawValue:)) ?? .nativeClarity
    }

    var id: String { rawValue }
    var title: String {
        switch self {
        case .nativeClarity: return L10n.tr("原生超清（推荐）")
        case .nativeSmooth: return L10n.tr("原生流畅")
        case .compatibility: return L10n.tr("低负载兼容")
        }
    }
    var detail: String {
        switch self {
        case .nativeClarity: return L10n.tr("保留原生细节，最高 30 fps，适合阅读。")
        case .nativeSmooth: return L10n.tr("保留原生细节，最高 60 fps，适合动态画面。")
        case .compatibility: return L10n.tr("最高 1920 像素，降低手机和网络负载。")
        }
    }
    var maxSize: Int { self == .compatibility ? 1920 : 0 }
    var videoBitRateMbps: Int { self == .compatibility ? 12 : 24 }
    var maxFPS: Int { self == .nativeSmooth ? 60 : 30 }
    func videoBufferMilliseconds(isWireless: Bool) -> Int { isWireless ? 80 : 0 }

    var configurationSummary: String {
        let size = maxSize == 0 ? L10n.tr("原生分辨率") : L10n.tr("长边 ≤ %@ px", String(maxSize))
        return L10n.tr("%@ · 目标 %@ Mbps · 上限 %@ fps", size, String(videoBitRateMbps), String(maxFPS))
    }
}
