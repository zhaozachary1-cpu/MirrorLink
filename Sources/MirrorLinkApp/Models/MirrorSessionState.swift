import Foundation

enum MirrorSessionState: Equatable {
    case idle
    case starting
    case mirroring
    case stopping
    case failed(String)

    var title: String {
        switch self {
        case .idle: return "未开始投屏"
        case .starting: return "正在启动投屏…"
        case .mirroring: return "正在投屏"
        case .stopping: return "正在停止投屏…"
        case .failed: return "投屏失败"
        }
    }

    var symbolName: String {
        switch self {
        case .idle: return "rectangle.on.rectangle"
        case .starting: return "hourglass"
        case .mirroring: return "rectangle.on.rectangle.fill"
        case .stopping: return "stop.circle"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }

    var isActive: Bool {
        self == .starting || self == .mirroring || self == .stopping
    }
}
