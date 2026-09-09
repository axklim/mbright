import CoreGraphics
import MBrightCore
import MBrightIPC

/// Makes the other displays follow the main display. Handles `set` and
/// `adjust` ahead of `RequestHandler` so the daemon's own writes to main
/// propagate inside the request; changes made by anyone else arrive
/// through the brightness change notification.
///
/// Main's last known percent is kept in every mode. A notification whose
/// value equals it is the daemon's own write and is ignored; that is the
/// whole loop guard, since a secondary's notification is never acted on.
@MainActor
public final class BrightnessSync {
    public private(set) var mode: SyncMode = .off
    public var lastMain: Int? { main?.percent }

    private let controller: BrightnessController
    private let log: (String) -> Void
    private var main: (id: CGDirectDisplayID, percent: Int)?

    public init(controller: BrightnessController, log: @escaping (String) -> Void) {
        self.controller = controller
        self.log = log
        main = readMain()
    }

    public func setMode(_ new: SyncMode) {
        mode = new
        snap()
    }

    public func displaysChanged() {
        main = readMain()
        snap()
    }

    public func brightnessChanged(id: CGDirectDisplayID, percent: Int) {
        guard let current = main, id == current.id, percent != current.percent else { return }
        main = (id, percent)
        do {
            try propagate(from: current.percent, to: percent)
        } catch {
            log("Warning: sync: \(error)")
        }
    }

    /// `nil` for requests that are not brightness writes.
    public func handle(_ request: Request) -> Response? {
        switch request {
        case let .set(percent, target):
            return respond(target) { try controller.set(percent: percent, target: target) }
        case let .adjust(delta, target):
            return respond(target) { try controller.adjust(delta: delta, target: target) }
        default:
            return nil
        }
    }

    // MARK: - Internals

    /// The write's own errors come back unchanged so the CLI prints what it
    /// printed before. A partial failure still wrote some displays, so the
    /// post-write bookkeeping runs and its failures are added to the list.
    private func respond(_ target: Target, _ write: () throws -> Void) -> Response {
        var failures: [String] = []
        do {
            try write()
        } catch MBrightError.partialFailure(let list) {
            failures = list
        } catch let error as MBrightError {
            return .failure(error)
        } catch {
            return .failure(.daemonFailure("\(error)"))
        }
        do {
            try didWrite(target)
        } catch MBrightError.partialFailure(let list) {
            failures += list
        } catch {
            failures.append("sync: \(error)")
        }
        return failures.isEmpty ? .ok : .failure(.partialFailure(failures: failures))
    }

    /// Refreshes main if it was written; propagates only when main was the
    /// one display written, since `--all` already addressed every display.
    private func didWrite(_ target: Target) throws {
        guard let current = main else { return }
        let written = try controller.resolve(target)
        // A main that cannot be read back keeps its old value; the write's
        // own error already covers that display.
        guard written.contains(where: { $0.id == current.id }),
              let now = try? controller.get(.id(current.id)) else { return }
        main = (current.id, now)
        guard written.count == 1 else { return }
        try propagate(from: current.percent, to: now)
    }

    private func snap() {
        guard mode == .full, let current = main else { return }
        do {
            try propagate(from: current.percent, to: current.percent)
        } catch {
            log("Warning: sync: \(error)")
        }
    }

    private func propagate(from previous: Int, to now: Int) throws {
        guard let current = main, mode != .off else { return }
        if mode == .relative, now == previous { return }
        var failures: [String] = []
        for reading in try controller.readings()
        where reading.display.id != current.id && reading.state != .unsupported {
            let target = Target.id(reading.display.id)
            do {
                if mode == .full {
                    try controller.set(percent: now, target: target)
                } else {
                    try controller.adjust(delta: now - previous, target: target)
                }
            } catch MBrightError.partialFailure(let list) {
                failures += list
            } catch {
                failures.append("\(reading.display.name): \(error)")
            }
        }
        guard failures.isEmpty else { throw MBrightError.partialFailure(failures: failures) }
    }

    private func readMain() -> (id: CGDirectDisplayID, percent: Int)? {
        guard let display = try? controller.resolve(.main).first,
              let percent = try? controller.get(.id(display.id)) else { return nil }
        return (display.id, percent)
    }
}
