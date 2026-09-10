import CoreGraphics
import Foundation

/// Brightness change notifications from DisplayServices, so a long-lived
/// process learns about writes made by anyone: the CLI, System Settings,
/// keyboard keys, or a display's own auto-brightness.
///
/// The symbol is private and optional: when it is missing the observer
/// reports `isAvailable == false` and callers fall back to re-reading on
/// demand. Signature confirmed against Lunar and SketchyBar:
/// `int Register(CGDirectDisplayID display, CGDirectDisplayID observer, CFNotificationCallback)`,
/// with the new value in `userInfo["value"]` as a Double.
public final class DisplayServicesBrightnessObserver: @unchecked Sendable {
    public typealias Handler = @Sendable (CGDirectDisplayID, Float) -> Void

    private typealias RegisterFn = @convention(c) (CGDirectDisplayID, CGDirectDisplayID, CFNotificationCallback) -> Int32
    private typealias UnregisterFn = @convention(c) (CGDirectDisplayID, CGDirectDisplayID) -> Int32

    private let registerFn: RegisterFn?
    private let unregisterFn: UnregisterFn?
    private let lock = NSLock()
    private var observed: Set<CGDirectDisplayID> = []
    private let handler: Handler
    private let log: @Sendable (String) -> Void

    /// The C callback cannot capture context, so live observers are looked
    /// up here by the display ID DisplayServices hands back.
    nonisolated(unsafe) private static var registry: [CGDirectDisplayID: DisplayServicesBrightnessObserver] = [:]
    private static let registryLock = NSLock()

    public init(log: @escaping @Sendable (String) -> Void = { _ in }, handler: @escaping Handler) {
        self.handler = handler
        self.log = log
        let handle = dlopen(DisplayServicesBackend.frameworkPath, RTLD_LAZY)
        registerFn = handle.flatMap { dlsym($0, "DisplayServicesRegisterForBrightnessChangeNotifications") }
            .map { unsafeBitCast($0, to: RegisterFn.self) }
        unregisterFn = handle.flatMap { dlsym($0, "DisplayServicesUnregisterForBrightnessChangeNotifications") }
            .map { unsafeBitCast($0, to: UnregisterFn.self) }
    }

    public var isAvailable: Bool { registerFn != nil && unregisterFn != nil }

    /// Observes every display in `ids` not already observed and drops the
    /// ones that went away. Safe to call after every hotplug.
    public func observe(_ ids: [CGDirectDisplayID]) {
        guard let registerFn, let unregisterFn else { return }
        let wanted = Set(ids)
        lock.lock()
        let added = wanted.subtracting(observed)
        let removed = observed.subtracting(wanted)
        observed = wanted
        lock.unlock()

        for id in removed {
            Self.registryLock.withLock { _ = Self.registry.removeValue(forKey: id) }
            let code = unregisterFn(id, id)
            log("observer: unregister \(id) -> \(code)")
        }
        for id in added {
            Self.registryLock.withLock { Self.registry[id] = self }
            let code = registerFn(id, id, Self.callback)
            log("observer: register \(id) -> \(code)")
            if code != 0 {
                Self.registryLock.withLock { _ = Self.registry.removeValue(forKey: id) }
            }
        }
        if added.isEmpty, removed.isEmpty { log("observer: observing \(wanted.sorted()), nothing to change") }
    }

    private static let callback: CFNotificationCallback = { _, observer, _, _, userInfo in
        let id = CGDirectDisplayID(truncatingIfNeeded: UInt(bitPattern: observer))
        guard let value = (userInfo as NSDictionary?)?["value"] as? Double,
              let validated = DeviceValue.validated(Float(value)) else { return }
        let target = registryLock.withLock { registry[id] }
        target?.handler(id, validated)
    }
}
