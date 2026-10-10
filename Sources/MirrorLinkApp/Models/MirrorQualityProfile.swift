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
        case .nativeClarity: return "原生超清（推荐）"
        case .nativeSmooth: return "原生流畅"
        case .compatibility: return "低负载兼容"
        }
    }
    var detail: String {
        switch self {
        case .nativeClarity: return "保留手机原生细节，限制到最高 30 fps，优先文字清晰与持续使用。"
        case .nativeSmooth: return "保留手机原生细节，最高 60 fps；适合滑动和动态内容，手机与网络负载更高。"
        case .compatibility: return "主动限制画面长边到 1920 像素以减轻负载，适合带宽不足、多设备或编码失败时使用。"
        }
    }
    var maxSize: Int { self == .compatibility ? 1920 : 0 }
    var videoBitRateMbps: Int { self == .compatibility ? 12 : 24 }
    var maxFPS: Int { self == .nativeSmooth ? 60 : 30 }
    func videoBufferMilliseconds(isWireless: Bool) -> Int { isWireless ? 80 : 0 }

    var configurationSummary: String {
        let size = maxSize == 0 ? "原生分辨率" : "长边 ≤ \(maxSize) px"
        return "\(size) · 目标 \(videoBitRateMbps) Mbps · 上限 \(maxFPS) fps"
    }
}
