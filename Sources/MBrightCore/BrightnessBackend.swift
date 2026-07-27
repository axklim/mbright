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

/// Brightness as reported for one display.
public enum BrightnessState: Equatable, Sendable {
    case percent(Int)
    /// The display reports no brightness control.
    case unsupported
    /// Brightness control is reported available, but the read failed.
    case failed(String)
}

/// A display paired with its current brightness state.
public struct DisplayReading: Equatable, Sendable {
    public let display: DisplayInfo
    public let state: BrightnessState

    public init(display: DisplayInfo, state: BrightnessState) {
        self.display = display
        self.state = state
    }
}
