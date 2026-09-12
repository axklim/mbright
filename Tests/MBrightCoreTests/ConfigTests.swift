import Foundation
import Testing
@testable import MBrightCore

@Test func configDefaultsAreLoginOffUIOnSyncOffDebugOffDefaultHotkeys() {
    #expect(Config() == Config(login: false, ui: true, sync: .off, debug: false, hotkeys: Hotkey.defaults))
}

@Test func configDecodesHotkeysAndTreatsMissingAsDefaultsAndEmptyAsOff() throws {
    let decoder = JSONDecoder()
    #expect(try decoder.decode(Config.self, from: Data("{}".utf8)).hotkeys == Hotkey.defaults)
    #expect(try decoder.decode(Config.self, from: Data(#"{"hotkeys": []}"#.utf8)).hotkeys == [])
    let json = #"{"hotkeys": [{"keys": "cmd+f5", "action": "up", "display": "all", "step": 25}]}"#
    #expect(try decoder.decode(Config.self, from: Data(json.utf8)).hotkeys
        == [Hotkey(keys: try KeyCombination(parsing: "cmd+f5"), action: .up, display: .all, step: 25)])
    #expect(throws: MBrightError.invalidHotkey(keys: "cmd+f99", reason: "unknown key 'f99'")) {
        try decoder.decode(Config.self, from: Data(#"{"hotkeys": [{"keys": "cmd+f99", "action": "up"}]}"#.utf8))
    }
}

@Test func configDecodesDebug() throws {
    let decoder = JSONDecoder()
    #expect(try decoder.decode(Config.self, from: Data(#"{"debug": true}"#.utf8)) == Config(debug: true))
    #expect(try decoder.decode(Config.self, from: Data(#"{"debug": false}"#.utf8)) == Config())
}

@Test func configDecodesMissingKeysAsDefaultsAndIgnoresUnknownKeys() throws {
    let decoder = JSONDecoder()
    #expect(try decoder.decode(Config.self, from: Data("{}".utf8)) == Config())
    #expect(try decoder.decode(Config.self, from: Data(#"{"login": true}"#.utf8)) == Config(login: true, ui: true))
    #expect(try decoder.decode(Config.self, from: Data(#"{"login": true, "ui": false, "future": 1}"#.utf8))
        == Config(login: true, ui: false))
}

@Test func configDecodesEverySyncModeAndRejectsUnknownOnes() throws {
    let decoder = JSONDecoder()
    for mode in SyncMode.allCases {
        let json = #"{"sync": "\#(mode.rawValue)"}"#
        #expect(try decoder.decode(Config.self, from: Data(json.utf8)) == Config(sync: mode))
    }
    #expect(throws: DecodingError.self) {
        try decoder.decode(Config.self, from: Data(#"{"sync": "sideways"}"#.utf8))
    }
}

@Test func configEncodesEveryKey() throws {
    let data = try JSONEncoder().encode(Config(login: true, ui: false, sync: .relative, debug: true))
    let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    #expect(object?["login"] as? Bool == true)
    #expect(object?["ui"] as? Bool == false)
    #expect(object?["sync"] as? String == "relative")
    #expect(object?["debug"] as? Bool == true)
    #expect((object?["hotkeys"] as? [[String: Any]])?.count == 4)
    #expect(object?.count == 5)
}

@Test func configStatusRoundTrips() throws {
    let status = ConfigStatus(config: Config(login: true, ui: true), path: "/x/config.json", onDisk: true)
    let decoded = try JSONDecoder().decode(ConfigStatus.self, from: try JSONEncoder().encode(status))
    #expect(decoded == status)
}

@Test func newErrorsHaveMessages() {
    #expect(MBrightError.loginUnavailable(reason: "running from /tmp/mbrightd").description
        == "Launch at login needs mbright installed as an app: running from /tmp/mbrightd. Run 'make install' first.")
    #expect(MBrightError.configInvalid(path: "/x/config.json", reason: "bad json").description
        == "Could not read /x/config.json: bad json")
}
