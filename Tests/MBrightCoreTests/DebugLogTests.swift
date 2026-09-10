import Foundation
import Testing
@testable import MBrightCore

private func scratch() -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mbright-debuglog-\(UUID().uuidString)")
    return url
}

@Test func debugLogPathFollowsXDGStateHome() {
    let home = URL(fileURLWithPath: "/Users/me")
    #expect(DebugLog.resolve(name: "mbrightd", environment: ["XDG_STATE_HOME": "/xdg"], home: home).path
        == "/xdg/mbright/mbrightd.log")
    #expect(DebugLog.resolve(name: "mbright-menubar", environment: [:], home: home).path
        == "/Users/me/.local/state/mbright/mbright-menubar.log")
    #expect(DebugLog.resolve(name: "mbrightd", environment: ["XDG_STATE_HOME": ""], home: home).path
        == "/Users/me/.local/state/mbright/mbrightd.log")
    #expect(DebugLog.resolve(name: "mbrightd", environment: ["XDG_STATE_HOME": "rel"], home: home).path
        == "/Users/me/.local/state/mbright/mbrightd.log")
}

@Test func disabledLogWritesNothingAndCreatesNoFile() {
    let dir = scratch()
    defer { try? FileManager.default.removeItem(at: dir) }
    let log = DebugLog(url: dir.appendingPathComponent("nested/x.log"))
    #expect(log.isEnabled == false)
    log.log("dropped")
    #expect(FileManager.default.fileExists(atPath: dir.path) == false)
}

@Test func enabledLogAppendsTimestampedLinesAndSurvivesToggling() throws {
    let dir = scratch()
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("nested/x.log")
    let log = DebugLog(url: url)

    log.setEnabled(true)
    #expect(log.isEnabled)
    log.log("first")
    log.setEnabled(false)
    log.log("dropped")
    log.setEnabled(true)
    log.log("second")

    let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
    #expect(lines.count == 2)
    #expect(lines[0].hasSuffix(" first"))
    #expect(lines[1].hasSuffix(" second"))
    // "2026-09-10 16:07:54.123 " precedes every message.
    #expect(lines[0].prefix(23).range(of: #"^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d{3}$"#, options: .regularExpression) != nil)
}

@Test func enablingTwiceIsIdempotentAndMessagesAreLazy() {
    let dir = scratch()
    defer { try? FileManager.default.removeItem(at: dir) }
    let log = DebugLog(url: dir.appendingPathComponent("x.log"))
    var evaluated = 0
    log.log("\(evaluated += 1)")
    #expect(evaluated == 0)
    log.setEnabled(true)
    log.setEnabled(true)
    log.log("\(evaluated += 1)")
    #expect(evaluated == 1)
}
