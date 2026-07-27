import CoreGraphics

/// Source of the currently-online displays.
public protocol DisplayEnumerating: Sendable {
    func onlineDisplays() throws -> [DisplayInfo]
}

/// Reads and writes brightness on the unit interval (0.0-1.0).
public protocol BrightnessBackend: Sendable {
    func canChangeBrightness(_ id: CGDirectDisplayID) -> Bool
    func getBrightness(_ id: CGDirectDisplayID) throws -> Float
    func setBrightness(_ id: CGDirectDisplayID, _ value: Float) throws
}

/// Which displays a command applies to.
public enum Target: Equatable, Sendable {
    case main
    case all
    case selector(String)
}

/// A display paired with its current brightness, or nil if unsupported.
public struct DisplayReading: Equatable, Sendable {
    public let display: DisplayInfo
    public let percent: Int?

    public init(display: DisplayInfo, percent: Int?) {
        self.display = display
        self.percent = percent
    }
}
