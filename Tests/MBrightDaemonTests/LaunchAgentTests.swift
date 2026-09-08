import Foundation
import Testing
@testable import MBrightDaemon

@Test func launchAgentPlistPointsAtProgramWithoutKeepAlive() throws {
    let agent = LaunchAgent(program: "/Applications/mbright.app/Contents/MacOS/mbright-menubar")
    let decoded = try PropertyListSerialization.propertyList(from: agent.plistData(), format: nil) as? [String: Any]
    #expect(decoded?["Label"] as? String == "com.axklim.mbright")
    #expect(decoded?["ProgramArguments"] as? [String] == ["/Applications/mbright.app/Contents/MacOS/mbright-menubar"])
    #expect(decoded?["RunAtLoad"] as? Bool == true)
    #expect(decoded?["KeepAlive"] == nil)
    #expect(decoded?["EnvironmentVariables"] == nil)
    #expect(LaunchAgent.defaultFileURL.path.hasSuffix("/Library/LaunchAgents/com.axklim.mbright.plist"))
}

@Test func launchAgentPinsXDGRuntimeDirForLaunchd() throws {
    let agent = LaunchAgent(program: "/x/mbrightd", environment: ["XDG_RUNTIME_DIR": "/run/user/501"])
    let decoded = try PropertyListSerialization.propertyList(from: agent.plistData(), format: nil) as? [String: Any]
    #expect(decoded?["EnvironmentVariables"] as? [String: String] == ["XDG_RUNTIME_DIR": "/run/user/501"])
}

@Test func relevantEnvironmentKeepsOnlyAValidRuntimeDir() {
    #expect(LaunchAgent.relevantEnvironment(["XDG_RUNTIME_DIR": "/run/user/501", "PATH": "/bin", "HOME": "/h"])
        == ["XDG_RUNTIME_DIR": "/run/user/501"])
    #expect(LaunchAgent.relevantEnvironment(["XDG_RUNTIME_DIR": ""]).isEmpty)
    #expect(LaunchAgent.relevantEnvironment(["XDG_RUNTIME_DIR": "rel"]).isEmpty)
    #expect(LaunchAgent.relevantEnvironment([:]).isEmpty)
}

@Test func launchAgentWritesReadsBackAndRemoves() throws {
    let dir = temporaryDirectory("agent")
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("nested/a.plist")
    let agent = LaunchAgent(program: "/x/mbrightd", environment: ["XDG_RUNTIME_DIR": "/run/user/501"])

    #expect(LaunchAgent.read(at: url) == nil)
    try agent.write(to: url)
    #expect(LaunchAgent.read(at: url) == agent)
    try LaunchAgent.remove(at: url)
    #expect(LaunchAgent.read(at: url) == nil)
    // Removing twice must not throw on the missing file.
    try LaunchAgent.remove(at: url)
}

@Test func readIgnoresForeignOrBrokenPlists() throws {
    let dir = temporaryDirectory("agent")
    defer { try? FileManager.default.removeItem(at: dir) }
    let foreign = dir.appendingPathComponent("foreign.plist")
    let data = try PropertyListSerialization.data(
        fromPropertyList: ["Label": "com.other", "ProgramArguments": ["/x"]], format: .xml, options: 0)
    try data.write(to: foreign)
    #expect(LaunchAgent.read(at: foreign) == nil)

    let broken = dir.appendingPathComponent("broken.plist")
    try Data("not a plist".utf8).write(to: broken)
    #expect(LaunchAgent.read(at: broken) == nil)
}
