import Foundation
import CoreGraphics

/// Brightness via the private DisplayServices framework, resolved at runtime.
///
/// This is private API with no public header, so every symbol lookup is
/// checked and reports exactly what is missing rather than crashing.
public final class DisplayServicesBackend: BrightnessBackend, @unchecked Sendable {
    private typealias CanChangeFn = @convention(c) (CGDirectDisplayID) -> Bool
    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    public static let frameworkPath =
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"

    private let canChangeFn: CanChangeFn
    private let getFn: GetFn
    private let setFn: SetFn
    /// Bound for a future --fade flag. Deliberately optional and never required:
    /// v1 does not call it, so a missing symbol must not break the whole tool.
    private let setSmoothFn: SetFn?

    public init() throws {
        guard let handle = dlopen(Self.frameworkPath, RTLD_LAZY) else {
            let reason = dlerror().map { String(cString: $0) } ?? "unknown error"
            throw MBrightError.frameworkUnavailable(path: Self.frameworkPath, reason: reason)
        }

        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString

        func required<T>(_ name: String, as type: T.Type) throws -> T {
            guard let symbol = dlsym(handle, name) else {
                throw MBrightError.symbolUnavailable(name: name, osVersion: osVersion)
            }
            return unsafeBitCast(symbol, to: type)
        }

        func optional<T>(_ name: String, as type: T.Type) -> T? {
            dlsym(handle, name).map { unsafeBitCast($0, to: type) }
        }

        canChangeFn = try required("DisplayServicesCanChangeBrightness", as: CanChangeFn.self)
        getFn = try required("DisplayServicesGetBrightness", as: GetFn.self)
        setFn = try required("DisplayServicesSetBrightness", as: SetFn.self)
        setSmoothFn = optional("DisplayServicesSetBrightnessSmooth", as: SetFn.self)
    }

    public func canChangeBrightness(_ id: CGDirectDisplayID) -> Bool {
        canChangeFn(id)
    }

    public func getBrightness(_ id: CGDirectDisplayID) throws -> Float {
        // Sentinel: a successful call that never writes the out-parameter must be
        // detectable, not indistinguishable from a fully dark display.
        var value: Float = -1
        let code = getFn(id, &value)
        guard code == 0 else {
            throw MBrightError.operationFailed(display: "\(id)", code: code)
        }
        // DisplayServices is private API with no documented contract. A malformed
        // success must become a typed error, never a trap in Percent.fromDevice.
        guard value.isFinite, (0...1).contains(value) else {
            throw MBrightError.operationFailed(display: "\(id)", code: code)
        }
        return value
    }

    public func setBrightness(_ id: CGDirectDisplayID, _ value: Float) throws {
        let code = setFn(id, value)
        guard code == 0 else {
            throw MBrightError.operationFailed(display: "\(id)", code: code)
        }
    }
}
