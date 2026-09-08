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

/// Quit in the menu bar app stops the daemon it is talking to.
@MainActor
@Test func shutdownDaemonSendsShutdownWhenConnected() async throws {
    let received = Requests()
    let harness = try Harness { request in
        received.record(request)
        return request == .shutdown ? .ok : makeHandler().handle(request)
    }
    let connection = DaemonConnection(path: harness.path)
    var connected = false
    connection.send(.version) { _ in connected = true }
    await waitUntil { connected }

    var finished = false
    connection.shutdownDaemon { finished = true }
    await waitUntil { finished }
    #expect(received.values.contains(.shutdown))
}

/// With no daemon to talk to there is nothing to stop; in particular one
/// must not be spawned just to be told to exit.
@MainActor
@Test func shutdownDaemonWithoutConnectionDoesNotStartOne() async throws {
    let path = temporarySocketPath()
    let connection = DaemonConnection(path: path)

    var finished = false
    connection.shutdownDaemon { finished = true }
    await waitUntil { finished }
    #expect(finished)
    try await Task.sleep(nanoseconds: 200_000_000)
    #expect(!connection.isConnected)
    #expect(!FileManager.default.fileExists(atPath: path))
}

private final class Requests: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Request] = []
    var values: [Request] { lock.withLock { storage } }
    func record(_ request: Request) { lock.withLock { storage.append(request) } }
}
