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
public enum Target: Hashable, Sendable, Codable {
    case main
    /// The first online display that is not main. Produced by hotkeys;
    /// the CLI never produces it.
    case secondary
    case all
    case selector(String)
    /// Exactly one display by `CGDirectDisplayID`. Used by clients that
    /// already hold an ID (the menu bar app); the CLI never produces it.
    case id(CGDirectDisplayID)
}

extension Target {
    /// Resolves CLI flags to a target. `display` and `all` are mutually exclusive.
    public static func resolve(display: String?, all: Bool) throws -> Target {
        if all, display != nil { throw MBrightError.conflictingTargetFlags }
        if all { return .all }
        if let display { return .selector(display) }
        return .main
    }
}

/// Brightness as reported for one display.
public enum BrightnessState: Equatable, Sendable, Codable {
    case percent(Int)
    /// The display reports no brightness control.
    case unsupported
    /// Brightness control is reported available, but the read failed.
    case failed(String)
}

/// A display paired with its current brightness state.
public struct DisplayReading: Equatable, Sendable, Codable {
    public let display: DisplayInfo
    public let state: BrightnessState

    public init(display: DisplayInfo, state: BrightnessState) {
        self.display = display
        self.state = state
    }
}
