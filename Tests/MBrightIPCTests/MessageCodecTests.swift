import Foundation
import Testing
@testable import MBrightCore
@testable import MBrightIPC

private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
    let data = try LineCodec.encode(value)
    #expect(data.last == 0x0A)
    #expect(data.dropLast().contains(0x0A) == false)
    return try LineCodec.decode(T.self, from: data.dropLast())
}

@Test func clientMessagesRoundTrip() throws {
    let messages: [ClientMessage] = [
        ClientMessage(id: 1, request: .readings),
        ClientMessage(id: 2, request: .get(target: .main)),
        ClientMessage(id: 3, request: .set(percent: 80, target: .all)),
        ClientMessage(id: 4, request: .adjust(delta: -10, target: .selector("studio"))),
        ClientMessage(id: 5, request: .set(percent: 1, target: .id(3))),
        ClientMessage(id: 6, request: .subscribe),
        ClientMessage(id: 7, request: .version),
        ClientMessage(id: 8, request: .shutdown),
    ]
    for message in messages {
        #expect(try roundTrip(message) == message)
    }
}

@Test func serverMessagesRoundTrip() throws {
    let readings = [
        DisplayReading(display: studio, state: .percent(79)),
        DisplayReading(display: ultrafine, state: .unsupported),
        DisplayReading(display: ultrafine, state: .failed("boom")),
    ]
    let messages: [ServerMessage] = [
        .reply(id: 1, response: .readings(readings)),
        .reply(id: 2, response: .percent(42)),
        .reply(id: 3, response: .ok),
        .reply(id: 4, response: .version("0.2.0")),
        .reply(id: 5, response: .failure(.noMatch(selector: "x", available: ["a", "b"]))),
        .reply(id: 6, response: .failure(.operationFailed(displayID: 3, code: -1))),
        .reply(id: 7, response: .failure(.malformedBrightnessValue(displayID: 3, value: 1.5))),
        .reply(id: 8, response: .failure(.partialFailure(failures: ["a: b"]))),
        .event(.displaysChanged),
        .event(.brightnessChanged(id: 3, percent: 42)),
    ]
    for message in messages {
        #expect(try roundTrip(message) == message)
    }
}

@Test func errorDescriptionsSurviveTheWire() throws {
    let original = MBrightError.ambiguousSelector(selector: "l", candidates: ["LG", "LG 2"])
    let decoded = try roundTrip(Response.failure(original))
    guard case let .failure(error) = decoded else {
        Issue.record("expected failure")
        return
    }
    #expect(error.description == original.description)
}

@Test func lineBufferSplitsPartialAndMultipleLines() {
    var buffer = LineBuffer()
    #expect(buffer.append(Data("ab".utf8)).isEmpty)
    let first = buffer.append(Data("c\nde".utf8))
    #expect(first == [Data("abc".utf8)])
    let rest = buffer.append(Data("f\n\ng\n".utf8))
    #expect(rest == [Data("def".utf8), Data(), Data("g".utf8)])
    #expect(buffer.append(Data()).isEmpty)
}

@Test func socketPathFollowsXDGRuntimeDir() {
    #expect(SocketPath.resolve(environment: ["XDG_RUNTIME_DIR": "/run/user/501"], fallbackRuntimeDirectory: "/fb")
        == "/run/user/501/mbright/mbrightd.sock")
    // XDG: empty means unset, and a relative path is invalid, not resolved.
    #expect(SocketPath.resolve(environment: ["XDG_RUNTIME_DIR": ""], fallbackRuntimeDirectory: "/fb")
        == "/fb/mbright/mbrightd.sock")
    #expect(SocketPath.resolve(environment: ["XDG_RUNTIME_DIR": "relative/dir"], fallbackRuntimeDirectory: "/fb")
        == "/fb/mbright/mbrightd.sock")
}

@Test func socketPathDefaultIsPerUserAndShortEnough() {
    let fallback = SocketPath.resolve(environment: [:])
    #expect(fallback.hasPrefix("/"))
    #expect(fallback.hasSuffix("/mbright/mbrightd.sock"))
    #expect(fallback.utf8.count < 104)
}
