import Foundation
import Testing
@testable import MBrightCore
@testable import MBrightIPC

@Test func clientGetsRepliesMatchedById() throws {
    let harness = try Harness()
    let client = try BlockingClient(path: harness.path)
    #expect(try client.request(.version) == .version("9.9.9"))
    #expect(try client.request(.get(target: .main)) == .percent(50))
    #expect(try client.request(.get(target: .all)) == .failure(.getDoesNotSupportAll))
}

@Test func subscribedClientReceivesBroadcasts() throws {
    let harness = try Harness()
    let subscriber = try BlockingClient(path: harness.path)
    let bystander = try BlockingClient(path: harness.path)
    #expect(try subscriber.request(.subscribe) == .ok)

    harness.queue.sync { harness.server.broadcast(.displaysChanged) }
    #expect(try subscriber.waitForEvent() == .displaysChanged)

    // The bystander never subscribed, so its next reply is not preceded by
    // an event line; a request still completes normally.
    #expect(try bystander.request(.version) == .version("9.9.9"))
}

@Test func connectionCountTracksClients() throws {
    let harness = try Harness()
    let counts = Counts()
    harness.queue.sync {
        harness.server.onConnectionCountChanged = { counts.record($0) }
    }

    var client: BlockingClient? = try BlockingClient(path: harness.path)
    _ = try client?.request(.version)
    #expect(harness.queue.sync { harness.server.connectionCount } == 1)

    client = nil
    let deadline = Date().addingTimeInterval(2)
    while harness.queue.sync(execute: { harness.server.connectionCount }) != 0, Date() < deadline {
        usleep(10_000)
    }
    #expect(harness.queue.sync { harness.server.connectionCount } == 0)
    #expect(counts.values == [1, 0])
}

@Test func malformedRequestClosesTheConnection() throws {
    let harness = try Harness()
    let fd = try UnixSocket.connect(path: harness.path)
    defer { close(fd) }
    try UnixSocket.writeAll(fd, Data("this is not json\n".utf8))
    UnixSocket.setReceiveTimeout(fd, seconds: 2)
    #expect(try UnixSocket.read(fd).isEmpty)
}

@Test func staleSocketFileIsReplaced() throws {
    let path = temporarySocketPath()
    // Simulate a crash: a listener that closed its descriptor without
    // unlinking leaves a file nothing answers on.
    close(try UnixSocket.listen(path: path))
    #expect(FileManager.default.fileExists(atPath: path))

    let queue = DispatchQueue(label: "mbright.test.stale")
    let server = LineServer(path: path, queue: queue) { _ in .ok }
    try server.start()
    defer { queue.sync { server.stop() } }
    let client = try BlockingClient(path: path)
    #expect(try client.request(.version) == .ok)
}

@Test func liveDaemonIsNotEvicted() throws {
    let harness = try Harness()
    let rival = LineServer(path: harness.path, queue: harness.queue) { _ in .ok }
    #expect(throws: SocketError.self) { try rival.start() }
    let client = try BlockingClient(path: harness.path)
    #expect(try client.request(.version) == .version("9.9.9"))
}

@Test func connectWithoutSpawnReportsDaemonNotRunning() {
    let path = temporarySocketPath()
    #expect(throws: MBrightError.daemonNotRunning) {
        _ = try DaemonLauncher.connect(path: path, spawnIfNeeded: false)
    }
    #expect(MBrightError.daemonNotRunning.description.contains("--daemon-autostart"))
}

@Test func locateDaemonPrefersSiblingOverPath() throws {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mbright-locate-\(UUID().uuidString)")
    let sibling = dir.appendingPathComponent("bin")
    let onPath = dir.appendingPathComponent("path")
    try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: onPath, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let pathDaemon = onPath.appendingPathComponent("mbrightd").path
    FileManager.default.createFile(atPath: pathDaemon, contents: Data("#!/bin/sh\n".utf8),
                                   attributes: [.posixPermissions: 0o755])
    let executable = sibling.appendingPathComponent("mbright")

    #expect(DaemonLauncher.locateDaemon(executableURL: executable, environment: ["PATH": onPath.path]) == pathDaemon)

    let siblingDaemon = sibling.appendingPathComponent("mbrightd").path
    FileManager.default.createFile(atPath: siblingDaemon, contents: Data("#!/bin/sh\n".utf8),
                                   attributes: [.posixPermissions: 0o755])
    #expect(DaemonLauncher.locateDaemon(executableURL: executable, environment: ["PATH": onPath.path]) == siblingDaemon)
    #expect(DaemonLauncher.locateDaemon(executableURL: nil, environment: [:]) == nil)
}

private final class Counts: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Int] = []
    var values: [Int] { lock.withLock { storage } }
    func record(_ value: Int) { lock.withLock { storage.append(value) } }
}
