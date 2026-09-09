import CoreGraphics
@testable import MBrightCore

let studio = DisplayInfo(index: 0, id: 3, name: "Studio Display", vendor: "APP", isMain: true)
let ultrafine = DisplayInfo(index: 1, id: 2, name: "LG UltraFine", vendor: "GSM", isMain: false)

final class FakeEnumerator: DisplayEnumerating, @unchecked Sendable {
    var displays: [DisplayInfo]
    init(_ displays: [DisplayInfo] = [studio, ultrafine]) { self.displays = displays }
    func onlineDisplays() throws -> [DisplayInfo] { displays }
}

final class FakeBackend: BrightnessBackend, @unchecked Sendable {
    var values: [CGDirectDisplayID: Float]
    /// IDs that report brightness control as unavailable.
    var unsupported: Set<CGDirectDisplayID> = []
    /// IDs whose set/get calls throw.
    var failing: Set<CGDirectDisplayID> = []
    var writes: [(id: CGDirectDisplayID, value: Float)] = []

    init(values: [CGDirectDisplayID: Float] = [3: 0.5, 2: 0.5]) { self.values = values }

    func canChangeBrightness(_ id: CGDirectDisplayID) -> Bool { !unsupported.contains(id) }

    func getBrightness(_ id: CGDirectDisplayID) throws -> Float {
        if failing.contains(id) { throw MBrightError.operationFailed(displayID: id, code: -1) }
        return values[id] ?? 0
    }

    func setBrightness(_ id: CGDirectDisplayID, _ value: Float) throws {
        if failing.contains(id) { throw MBrightError.operationFailed(displayID: id, code: -1) }
        values[id] = value
        writes.append((id, value))
    }

    /// Current value of one display as a percent, for assertions.
    func percent(_ id: CGDirectDisplayID) -> Int { Percent.fromDevice(values[id] ?? 0) }
}
