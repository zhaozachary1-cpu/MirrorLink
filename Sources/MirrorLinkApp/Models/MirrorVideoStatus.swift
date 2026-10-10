import Foundation

struct VideoResolution: Equatable {
    let width: Int
    let height: Int
    var displayText: String { "\(width) × \(height)" }
    var pixelCount: Int { width * height }

    // A rotation swaps width and height without losing source pixels.
    func isSmaller(than other: Self) -> Bool {
        min(width, height) < min(other.width, other.height)
            || max(width, height) < max(other.width, other.height)
    }

    private static let pattern = try! NSRegularExpression(pattern: #"^INFO:\s+Texture:\s+([0-9]{1,5})x([0-9]{1,5})$"#)
    static func parse(logLine: String) -> Self? {
        let line = logLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = pattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let wRange = Range(match.range(at: 1), in: line),
              let hRange = Range(match.range(at: 2), in: line),
              let width = Int(line[wRange]), let height = Int(line[hRange]),
              (1...16384).contains(width), (1...16384).contains(height) else { return nil }
        return Self(width: width, height: height)
    }
}

struct MirrorVideoStatus: Equatable {
    let profile: MirrorQualityProfile
    let isWireless: Bool
    private(set) var resolution: VideoResolution?
    private(set) var initialResolution: VideoResolution?
    private(set) var encoderNotice: String?

    var configurationSummary: String {
        "\(profile.configurationSummary) · H.264 · 缓冲 \(profile.videoBufferMilliseconds(isWireless: isWireless)) ms"
    }
    var warning: String? {
        if let resolution, let initialResolution, resolution.isSmaller(than: initialResolution) {
            return "收到的画面尺寸已由 \(initialResolution.displayText) 减小为 \(resolution.displayText)。请检查手机显示设置或重新投屏。"
        }
        return encoderNotice
    }

    mutating func receive(_ size: VideoResolution) {
        if initialResolution == nil { initialResolution = size }
        resolution = size
    }

    mutating func noteEncoderConstraint() {
        encoderNotice = "手机编码器调整了画面参数，请以实际画面尺寸为准；若清晰度不足，可重新投屏或改用兼容档。"
    }
}
