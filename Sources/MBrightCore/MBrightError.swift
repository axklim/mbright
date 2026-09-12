import CoreGraphics

public enum MBrightError: Error, Equatable, CustomStringConvertible, Codable {
    case frameworkUnavailable(path: String, reason: String)
    case symbolUnavailable(name: String, osVersion: String)
    case enumerationFailed(code: Int32)
    case noDisplays
    case brightnessUnsupported(display: String)
    case operationFailed(displayID: CGDirectDisplayID, code: Int32)
    /// DisplayServices reported success but wrote a value outside the valid
    /// unit interval. Kept separate from `operationFailed` because the
    /// underlying `code` there is always 0 and would render a
    /// self-contradictory "(code 0)" for what is really a malformed-response
    /// diagnostic.
    case malformedBrightnessValue(displayID: CGDirectDisplayID, value: Float)
    case noMatch(selector: String, available: [String])
    case ambiguousSelector(selector: String, candidates: [String])
    case partialFailure(failures: [String])
    case getDoesNotSupportAll
    case conflictingTargetFlags
    /// A client could not reach `mbrightd` (not running and could not be
    /// started, or the connection dropped mid-request).
    case daemonUnavailable(reason: String)
    /// No daemon is listening and the caller chose not to start one.
    case daemonNotRunning
    /// The daemon hit an error that is not an `MBrightError`. Carries the
    /// description so the client can show it verbatim.
    case daemonFailure(String)
    /// Launch at login needs the daemon to run from the installed app
    /// bundle, so the plist has a stable program path to point at.
    case loginUnavailable(reason: String)
    /// The config file exists but could not be parsed.
    case configInvalid(path: String, reason: String)
    /// A `hotkeys` entry that does not parse. Surfaces through
    /// `configInvalid` when it comes from the file.
    case invalidHotkey(keys: String, reason: String)

    public var description: String {
        switch self {
        case let .frameworkUnavailable(path, reason):
            return "Could not load DisplayServices at \(path): \(reason)"
        case let .symbolUnavailable(name, osVersion):
            return """
                DisplayServices is missing the symbol '\(name)' on \(osVersion). \
                This private API changed; mbright needs updating.
                """
        case let .enumerationFailed(code):
            return "CGGetOnlineDisplayList failed with code \(code)"
        case .noDisplays:
            return "No online displays found"
        case .brightnessUnsupported:
            // Every call site already has the display name in hand (it's how
            // they got here) and prefixes it themselves, so it isn't repeated
            // here. "The display" keeps this a complete sentence on its own
            // (e.g. surfaced bare by `get`) without reintroducing the name.
            return "The display does not support brightness control"
        case let .operationFailed(displayID, code):
            return "Brightness operation failed on display \(displayID) (code \(code))"
        case let .malformedBrightnessValue(displayID, value):
            return "DisplayServices returned an out-of-range brightness value (\(value)) for display \(displayID)"
        case let .noMatch(selector, available):
            return "No display matches '\(selector)'. Available: \(available.joined(separator: ", "))"
        case let .ambiguousSelector(selector, candidates):
            return "'\(selector)' matches multiple displays: \(candidates.joined(separator: ", ")). Be more specific."
        case let .partialFailure(failures):
            return "Some displays failed:\n  " + failures.joined(separator: "\n  ")
        case .getDoesNotSupportAll:
            return "get reports a single display; use 'mbright list' for all displays"
        case .conflictingTargetFlags:
            return "--display and --all are mutually exclusive."
        case let .daemonUnavailable(reason):
            return "Could not reach mbrightd: \(reason)"
        case .daemonNotRunning:
            return "mbrightd is not running. Start it with 'mbright daemon start' or pass --daemon-autostart."
        case let .daemonFailure(message):
            return "mbrightd failed: \(message)"
        case let .loginUnavailable(reason):
            return "Launch at login needs mbright installed as an app: \(reason). Run 'make install' first."
        case let .configInvalid(path, reason):
            return "Could not read \(path): \(reason)"
        case let .invalidHotkey(keys, reason):
            return "Invalid hotkey '\(keys)': \(reason)"
        }
    }
}
