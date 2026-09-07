import Foundation

/// Where clients and the daemon meet, following the XDG Base Directory
/// specification: a runtime file belongs under `$XDG_RUNTIME_DIR`, in a
/// subdirectory named for the application.
///
/// macOS does not set `XDG_RUNTIME_DIR`. The spec says to fall back to a
/// directory with the same guarantees (per-user, local, private), which on
/// macOS is the `confstr(_CS_DARWIN_USER_TEMP_DIR)` directory launchd hands
/// each user.
public enum SocketPath {
    public static let xdgRuntimeVariable = "XDG_RUNTIME_DIR"
    public static let applicationDirectory = "mbright"
    public static let fileName = "mbrightd.sock"

    public static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fallbackRuntimeDirectory: @autoclosure () -> String = userTemporaryDirectory()
    ) -> String {
        let runtime = xdgDirectory(environment[xdgRuntimeVariable]) ?? fallbackRuntimeDirectory()
        return ((runtime as NSString).appendingPathComponent(applicationDirectory) as NSString)
            .appendingPathComponent(fileName)
    }

    /// XDG rules: unset or empty means "use the default", and a relative
    /// path is invalid and ignored rather than resolved.
    public static func xdgDirectory(_ value: String?) -> String? {
        guard let value, !value.isEmpty, value.hasPrefix("/") else { return nil }
        return value
    }

    public static func userTemporaryDirectory() -> String {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        let length = confstr(_CS_DARWIN_USER_TEMP_DIR, &buffer, buffer.count)
        if length > 0, length <= buffer.count {
            return String(decoding: buffer.prefix(length - 1).map { UInt8(bitPattern: $0) }, as: UTF8.self)
        }
        return NSTemporaryDirectory()
    }
}
