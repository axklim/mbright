import CoreGraphics
import MBrightCore

/// What the menu shows for one display. Pure data so the mapping from
/// readings is testable without AppKit.
public struct DisplayRow: Equatable, Sendable {
    public let id: CGDirectDisplayID
    public let name: String
    /// Present only when the display has a working slider.
    public let percent: Int?
    /// Shown instead of the percentage when there is no slider.
    public let detail: String?

    public init(id: CGDirectDisplayID, name: String, percent: Int?, detail: String?) {
        self.id = id
        self.name = name
        self.percent = percent
        self.detail = detail
    }
}

public enum MenuModel {
    public static func rows(from readings: [DisplayReading]) -> [DisplayRow] {
        readings.map { reading in
            switch reading.state {
            case let .percent(percent):
                return DisplayRow(id: reading.display.id, name: reading.display.name, percent: percent, detail: nil)
            case .unsupported:
                return DisplayRow(id: reading.display.id, name: reading.display.name, percent: nil,
                                  detail: "No brightness control")
            case let .failed(message):
                return DisplayRow(id: reading.display.id, name: reading.display.name, percent: nil,
                                  detail: "Error: \(message)")
            }
        }
    }
}
