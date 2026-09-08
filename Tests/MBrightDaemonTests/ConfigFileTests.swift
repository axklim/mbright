import Foundation
import Testing
@testable import MBrightCore
@testable import MBrightDaemon

func temporaryDirectory(_ name: String) -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mbright-\(name)-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Test func configPathFollowsXDGConfigHome() {
    let home = URL(fileURLWithPath: "/Users/me")
    #expect(ConfigFile.resolve(environment: ["XDG_CONFIG_HOME": "/xdg"], home: home).path == "/xdg/mbright/config.json")
    #expect(ConfigFile.resolve(environment: [:], home: home).path == "/Users/me/.config/mbright/config.json")
    #expect(ConfigFile.resolve(environment: ["XDG_CONFIG_HOME": ""], home: home).path == "/Users/me/.config/mbright/config.json")
    #expect(ConfigFile.resolve(environment: ["XDG_CONFIG_HOME": "rel"], home: home).path == "/Users/me/.config/mbright/config.json")
}

@Test func missingFileLoadsAsNil() throws {
    let dir = temporaryDirectory("config")
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = ConfigFile(url: dir.appendingPathComponent("config.json"))
    #expect(file.exists == false)
    #expect(try file.load() == nil)
}

@Test func saveCreatesDirectoryAndLoadReadsBack() throws {
    let dir = temporaryDirectory("config")
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = ConfigFile(url: dir.appendingPathComponent("nested/config.json"))
    try file.save(Config(login: true, ui: false))
    #expect(file.exists)
    #expect(try file.load() == Config(login: true, ui: false))
    let text = try String(contentsOf: file.url, encoding: .utf8)
    #expect(text.contains("\"login\" : true"))
    #expect(text.hasSuffix("\n"))
}

@Test func malformedFileIsConfigInvalid() throws {
    let dir = temporaryDirectory("config")
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = ConfigFile(url: dir.appendingPathComponent("config.json"))
    try Data("{ nope".utf8).write(to: file.url)
    #expect(throws: MBrightError.self) { try file.load() }
    do {
        _ = try file.load()
    } catch let MBrightError.configInvalid(path, _) {
        #expect(path == file.url.path)
    }
}
