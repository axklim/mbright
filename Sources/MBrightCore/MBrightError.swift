public enum MBrightError: Error, Equatable, CustomStringConvertible {
    case frameworkUnavailable(path: String, reason: String)
    case symbolUnavailable(name: String, osVersion: String)
    case enumerationFailed(code: Int32)
    case noDisplays
    case brightnessUnsupported(display: String)
    case operationFailed(display: String, code: Int32)
    case noMatch(selector: String, available: [String])
    case ambiguousSelector(selector: String, candidates: [String])
    case partialFailure(failures: [String])

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
        case let .brightnessUnsupported(display):
            return "Display '\(display)' does not support brightness control"
        case let .operationFailed(display, code):
            return "Brightness operation failed on '\(display)' (code \(code))"
        case let .noMatch(selector, available):
            return "No display matches '\(selector)'. Available: \(available.joined(separator: ", "))"
        case let .ambiguousSelector(selector, candidates):
            return "'\(selector)' matches multiple displays: \(candidates.joined(separator: ", ")). Be more specific."
        case let .partialFailure(failures):
            return "Some displays failed:\n  " + failures.joined(separator: "\n  ")
        }
    }
}
