import CoreGraphics

/// Orchestrates display resolution, unit conversion, and clamping.
/// Hardware access is entirely behind `DisplayEnumerating` and `BrightnessBackend`.
public struct BrightnessController: Sendable {
    private let enumerator: DisplayEnumerating
    private let backend: BrightnessBackend

    public init(enumerator: DisplayEnumerating, backend: BrightnessBackend) {
        self.enumerator = enumerator
        self.backend = backend
    }

    /// Every display with its current brightness state. Distinguishes a
    /// display that reports no brightness control from one where the read
    /// itself failed — collapsing those into the same nil-like state would
    /// hide a real I/O failure behind a benign capability report.
    public func readings() throws -> [DisplayReading] {
        let displays = try enumerator.onlineDisplays()
        guard !displays.isEmpty else { throw MBrightError.noDisplays }

        return displays.map { display in
            guard backend.canChangeBrightness(display.id) else {
                return DisplayReading(display: display, state: .unsupported)
            }
            do {
                let value = try backend.getBrightness(display.id)
                return DisplayReading(display: display, state: .percent(Percent.fromDevice(value)))
            } catch {
                return DisplayReading(display: display, state: .failed("\(error)"))
            }
        }
    }

    public func get(_ target: Target) throws -> Int {
        guard target != .all else { throw MBrightError.getDoesNotSupportAll }
        let display = try resolve(target)[0]
        try ensureSupported(display)
        return Percent.fromDevice(try backend.getBrightness(display.id))
    }

    public func set(percent: Int, target: Target) throws {
        let value = Percent.toDevice(Percent.clamp(percent))
        try apply(target) { display in
            try backend.setBrightness(display.id, value)
        }
    }

    public func adjust(delta: Int, target: Target) throws {
        try apply(target) { display in
            let current = Percent.fromDevice(try backend.getBrightness(display.id))
            let next = Percent.clamp(current + delta)
            try backend.setBrightness(display.id, Percent.toDevice(next))
        }
    }

    // MARK: - Internals

    /// The displays a target names, in list order. Public so the daemon's
    /// sync can tell which displays a request wrote.
    public func resolve(_ target: Target) throws -> [DisplayInfo] {
        let displays = try enumerator.onlineDisplays()
        guard !displays.isEmpty else { throw MBrightError.noDisplays }

        switch target {
        case .all:
            return displays
        case .main:
            return [displays.first(where: \.isMain) ?? displays[0]]
        case .secondary:
            guard let display = displays.first(where: { !$0.isMain }) else {
                throw MBrightError.noMatch(selector: "secondary", available: displays.map(\.name))
            }
            return [display]
        case let .selector(selector):
            return [try DisplaySelector.resolve(selector, in: displays)]
        case let .id(id):
            guard let display = displays.first(where: { $0.id == id }) else {
                throw MBrightError.noMatch(selector: "\(id)", available: displays.map(\.name))
            }
            return [display]
        }
    }

    /// Runs `body` against every targeted display. A failure on one display
    /// does not abort the others; all errors are collected and rethrown so a
    /// partial success can never look like a clean run.
    private func apply(_ target: Target, _ body: (DisplayInfo) throws -> Void) throws {
        var failures: [String] = []

        for display in try resolve(target) {
            do {
                try ensureSupported(display)
                try body(display)
            } catch {
                failures.append("\(display.name): \(error)")
            }
        }

        guard failures.isEmpty else {
            throw MBrightError.partialFailure(failures: failures)
        }
    }

    private func ensureSupported(_ display: DisplayInfo) throws {
        guard backend.canChangeBrightness(display.id) else {
            throw MBrightError.brightnessUnsupported(display: display.name)
        }
    }
}
