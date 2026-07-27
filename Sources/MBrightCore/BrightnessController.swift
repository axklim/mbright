import CoreGraphics

/// Orchestrates display resolution, unit conversion, and clamping.
/// Hardware access is entirely behind `DisplayEnumerating` and `BrightnessBackend`.
public struct BrightnessController {
    private let enumerator: DisplayEnumerating
    private let backend: BrightnessBackend

    public init(enumerator: DisplayEnumerating, backend: BrightnessBackend) {
        self.enumerator = enumerator
        self.backend = backend
    }

    /// Every display with its current brightness; nil percent means the
    /// display reports no brightness control.
    public func readings() throws -> [DisplayReading] {
        try enumerator.onlineDisplays().map { display in
            guard backend.canChangeBrightness(display.id) else {
                return DisplayReading(display: display, percent: nil)
            }
            let value = try? backend.getBrightness(display.id)
            return DisplayReading(display: display, percent: value.map(Percent.fromDevice))
        }
    }

    public func get(_ target: Target) throws -> Int {
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

    func resolve(_ target: Target) throws -> [DisplayInfo] {
        let displays = try enumerator.onlineDisplays()
        guard !displays.isEmpty else { throw MBrightError.noDisplays }

        switch target {
        case .all:
            return displays
        case .main:
            return [displays.first(where: \.isMain) ?? displays[0]]
        case let .selector(selector):
            return [try DisplaySelector.resolve(selector, in: displays)]
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
