import Foundation
import Testing
@testable import MBrightCore
@testable import MBrightMenuBar

private let studio = DisplayInfo(index: 0, id: 3, name: "Studio Display", vendor: "APP", isMain: true)
private let ultrafine = DisplayInfo(index: 1, id: 2, name: "LG UltraFine", vendor: "GSM", isMain: false)

@Test func rowsKeepOrderAndMapEveryState() {
    let rows = MenuModel.rows(from: [
        DisplayReading(display: studio, state: .percent(79)),
        DisplayReading(display: ultrafine, state: .unsupported),
        DisplayReading(display: ultrafine, state: .failed("code -1")),
    ])
    #expect(rows == [
        DisplayRow(id: 3, name: "Studio Display", percent: 79, detail: nil),
        DisplayRow(id: 2, name: "LG UltraFine", percent: nil, detail: "No brightness control"),
        DisplayRow(id: 2, name: "LG UltraFine", percent: nil, detail: "Error: code -1"),
    ])
}

@Test func launchAgentPlistPointsAtExecutable() throws {
    let agent = LaunchAgent(executablePath: "/opt/homebrew/bin/mbright-menubar",
                            fileURL: URL(fileURLWithPath: "/dev/null"))
    let decoded = try PropertyListSerialization.propertyList(from: agent.plistData(), format: nil) as? [String: Any]
    #expect(decoded?["Label"] as? String == "com.axklim.mbright.menubar")
    #expect(decoded?["ProgramArguments"] as? [String] == ["/opt/homebrew/bin/mbright-menubar"])
    #expect(decoded?["RunAtLoad"] as? Bool == true)
    #expect(decoded?["EnvironmentVariables"] == nil)
    #expect(LaunchAgent.defaultFileURL.path.hasSuffix("/Library/LaunchAgents/com.axklim.mbright.menubar.plist"))
}

@Test func launchAgentPinsXDGRuntimeDirForLaunchd() throws {
    let agent = LaunchAgent(executablePath: "/x/mbright-menubar", fileURL: URL(fileURLWithPath: "/dev/null"),
                            environment: ["XDG_RUNTIME_DIR": "/run/user/501"])
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

@Test func launchAgentWritesAndRemovesItsFile() throws {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mbright-agent-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }
    let agent = LaunchAgent(executablePath: "/x/mbright-menubar", fileURL: dir.appendingPathComponent("a.plist"))

    #expect(agent.isEnabled == false)
    try agent.setEnabled(true)
    #expect(agent.isEnabled == true)
    try agent.setEnabled(false)
    #expect(agent.isEnabled == false)
    // Disabling twice must not throw on the missing file.
    try agent.setEnabled(false)
}
