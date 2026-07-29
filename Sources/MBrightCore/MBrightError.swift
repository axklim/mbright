import CoreGraphics

public enum MBrightError: Error, Equatable, CustomStringConvertible {
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
            // they got here) and prefixes it themselves, so it isn't repeated here.
            return "does not support brightness control"
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
        }
    }
}
