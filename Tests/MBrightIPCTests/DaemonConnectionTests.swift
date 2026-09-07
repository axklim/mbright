import Foundation
import Testing
@testable import MBrightCore
@testable import MBrightIPC

/// The menu bar app calls `subscribe()` and then `send(.readings)` in its
/// initializer, both before the first connect has finished. Every one of
/// those sends must land on the same socket: an extra connection nobody
/// reads stays subscribed on the daemon, and its receive buffer fills with
/// broadcasts until the daemon blocks writing to it.
@MainActor
@Test func sendsIssuedBeforeTheFirstConnectShareOneSocket() async throws {
    let harness = try Harness()
    let connection = DaemonConnection(path: harness.path)

    connection.subscribe()
    var response: Response?
    connection.send(.version) { response = $0 }

    await waitUntil { response != nil }
    #expect(response == .version("9.9.9"))
    // Any second connect is already finished by the time the first reply
    // arrives, but settle anyway so a slow one cannot pass unnoticed.
    try await Task.sleep(nanoseconds: 300_000_000)
    #expect(harness.connectionCount == 1)
}

@MainActor
private func waitUntil(seconds: Double = 5, _ condition: () -> Bool) async {
    let deadline = Date().addingTimeInterval(seconds)
    while !condition(), Date() < deadline {
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
}
