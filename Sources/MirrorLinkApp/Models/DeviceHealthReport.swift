import Foundation

enum DeviceHealthSeverity: String, Sendable { case success, warning, error, info }

struct DeviceHealthItem: Identifiable, Sendable {
    let id: String
    let severity: DeviceHealthSeverity
    let titleMessage: LocalizedMessage
    let detailMessage: LocalizedMessage
    let suggestionMessage: LocalizedMessage?
    var title: String { titleMessage.resolved }
    var detail: String { detailMessage.resolved }
    var suggestion: String? { suggestionMessage?.resolved }
}

struct DeviceHealthReport: Sendable {
    let checkedAt: Date
    let isReady: Bool
    let androidVersion: String?
    let model: String?
    let screenSize: String?
    let items: [DeviceHealthItem]
}
