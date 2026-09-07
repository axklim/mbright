import CoreGraphics
import Foundation
@testable import MBrightCore
@testable import MBrightIPC

let studio = DisplayInfo(index: 0, id: 3, name: "Studio Display", vendor: "APP", isMain: true)
let ultrafine = DisplayInfo(index: 1, id: 2, name: "LG UltraFine", vendor: "GSM", isMain: false)

final class FakeEnumerator: DisplayEnumerating, @unchecked Sendable {
    var displays: [DisplayInfo]
    init(_ displays: [DisplayInfo] = [studio, ultrafine]) { self.displays = displays }
    func onlineDisplays() throws -> [DisplayInfo] { displays }
}

final class FakeBackend: BrightnessBackend, @unchecked Sendable {
    var values: [CGDirectDisplayID: Float]
    var unsupported: Set<CGDirectDisplayID> = []
    var failing: Set<CGDirectDisplayID> = []
    private(set) var writes: [(id: CGDirectDisplayID, value: Float)] = []

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
}

func makeHandler(
    _ enumerator: FakeEnumerator = FakeEnumerator(),
    _ backend: FakeBackend = FakeBackend()
) -> RequestHandler {
    RequestHandler(controller: BrightnessController(enumerator: enumerator, backend: backend), version: "9.9.9")
}

/// A socket path unique to one test, short enough for sockaddr_un.
func temporarySocketPath() -> String {
    let directory = "mbright-test-\(UUID().uuidString.prefix(8))"
    return ((NSTemporaryDirectory() as NSString).appendingPathComponent(directory) as NSString)
        .appendingPathComponent("mbrightd.sock")
}
