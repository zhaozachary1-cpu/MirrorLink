import Foundation
import CoreGraphics

enum MirrorWindowLayout: String, CaseIterable, Identifiable {
    case automatic, sideBySide, grid
    var id: String { rawValue }
    static let preferenceKey = "MirrorLinkWindowLayout"
    var title: String {
        switch self {
        case .automatic: return L10n.tr("自动位置")
        case .sideBySide: return L10n.tr("并排排列")
        case .grid: return L10n.tr("网格排列")
        }
    }

    /// SDL uses top-left desktop coordinates. The caller provides the screen's
    /// usable bounds in that coordinate system; existing windows are untouched.
    func placement(index: Int, count: Int, screen: CGRect) -> MirrorWindowPlacement? {
        guard self != .automatic, count > 0, screen.width >= 240, screen.height >= 240 else { return nil }
        let columns = self == .sideBySide ? max(count, 1) : Int(ceil(sqrt(Double(count))))
        let rows = Int(ceil(Double(count) / Double(columns)))
        let cellWidth = screen.width / Double(columns)
        let cellHeight = screen.height / Double(rows)
        return MirrorWindowPlacement(x: Int(screen.minX + Double(index % columns) * cellWidth + 8),
                                     y: Int(screen.minY + Double(index / columns) * cellHeight + 8),
                                     width: max(120, Int(cellWidth - 16)), height: max(160, Int(cellHeight - 40)))
    }
}

struct MirrorWindowPlacement: Equatable {
    let x: Int
    let y: Int
    let width: Int
    let height: Int
    var arguments: [String] {
        ["--window-x=\(x)", "--window-y=\(y)", "--window-width=\(width)", "--window-height=\(height)"]
    }
}
