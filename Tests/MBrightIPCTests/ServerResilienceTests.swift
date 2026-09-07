import Foundation
import Testing
@testable import MBrightCore
@testable import MBrightIPC

/// A subscriber that stops reading must not take the daemon down with it.
/// Its socket buffer is 8 KiB; once full, a blocking write to it strands
/// the queue the server runs on, and every other client stops being served.
@Test func broadcastSurvivesASubscriberThatStoppedReading() throws {
    let harness = try Harness()

    let deaf = try UnixSocket.connect(path: harness.path)
    try UnixSocket.writeAll(deaf, try LineCodec.encode(ClientMessage(id: 1, request: .subscribe)))
    // Reading the reply proves the server registered the subscription.
    UnixSocket.setReceiveTimeout(deaf, seconds: 3)
    #expect(try !UnixSocket.read(deaf).isEmpty)

    // Far more than both socket buffers hold. Nobody reads any of it.
    for percent in 0..<1000 {
        harness.queue.async { harness.server.broadcast(.brightnessChanged(id: 3, percent: percent % 101)) }
    }

    let client = BlockingClient(fd: try UnixSocket.connect(path: harness.path), receiveTimeoutSeconds: 3)
    let response = try? client.request(.version)
    // Drain whatever the server queued, so a stranded write can finish and
    // cleanup cannot hang, then assert.
    UnixSocket.setReceiveTimeout(deaf, seconds: 1)
    while let data = try? UnixSocket.read(deaf), !data.isEmpty {}
    close(deaf)
    #expect(response == .version("9.9.9"))
}

/// The daemon must outlive its clients. A subscriber that closes while a
/// broadcast is already queued is written to before the EOF is noticed, and
/// an unguarded write to a closed peer raises SIGPIPE, whose default action
/// kills the process — the daemon exiting unasked, taking every other
/// client with it.
@Test func broadcastSurvivesASubscriberThatClosedMidFlight() throws {
    let harness = try Harness()

    let leaving = try UnixSocket.connect(path: harness.path)
    try UnixSocket.writeAll(leaving, try LineCodec.encode(ClientMessage(id: 1, request: .subscribe)))
    UnixSocket.setReceiveTimeout(leaving, seconds: 3)
    #expect(try !UnixSocket.read(leaving).isEmpty)

    // Hold the queue so the broadcast is ordered ahead of the EOF wake-up.
    let held = DispatchSemaphore(value: 0)
    harness.queue.async { held.wait() }
    harness.queue.async { harness.server.broadcast(.brightnessChanged(id: 3, percent: 42)) }
    close(leaving)
    held.signal()

    let client = BlockingClient(fd: try UnixSocket.connect(path: harness.path), receiveTimeoutSeconds: 3)
    #expect(try client.request(.version) == .version("9.9.9"))
}

/// A client must report a dead daemon, not die of SIGPIPE: the CLI's
/// contract is the same message and exit code it printed in-process.
@Test func aClientWhoseDaemonWentAwayGetsAnErrorNotASignal() throws {
    let harness = try Harness()
    let client = BlockingClient(fd: try UnixSocket.connect(path: harness.path), receiveTimeoutSeconds: 3)
    #expect(try client.request(.version) == .version("9.9.9"))

    harness.queue.sync { harness.server.stop() }
    #expect(throws: MBrightError.self) { _ = try client.request(.version) }
}
