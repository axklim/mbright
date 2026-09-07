import AppKit
import Foundation
import MBrightCore
import MBrightIPC

/// A single-pane settings window. The one setting is Launch at login.
@MainActor
final class SettingsWindowController {
    private let window: NSWindow
    private let launchAtLogin = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)
    private let status = NSTextField(wrappingLabelWithString: "")
    private let agent: LaunchAgent

    init() {
        let executable = Bundle.main.executableURL?.resolvingSymlinksInPath().path ?? CommandLine.arguments[0]
        agent = LaunchAgent(
            executablePath: executable,
            environment: LaunchAgent.relevantEnvironment(ProcessInfo.processInfo.environment))

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 130),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false)
        window.title = "mbright Settings"
        window.isReleasedWhenClosed = false

        launchAtLogin.target = self
        launchAtLogin.action = #selector(toggleLaunchAtLogin)

        status.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        status.textColor = .secondaryLabelColor

        let version = NSTextField(labelWithString: "mbright \(Version.current)")
        version.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        version.textColor = .tertiaryLabelColor

        let stack = NSStackView(views: [launchAtLogin, status, version])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        window.contentView = content
    }

    func show() {
        launchAtLogin.state = agent.isEnabled ? .on : .off
        var text = "Takes effect at the next login. Writes \(agent.fileURL.path)."
        if let runtime = agent.environment[SocketPath.xdgRuntimeVariable] {
            text += " Pins XDG_RUNTIME_DIR to \(runtime) so the app and the CLI share one daemon."
        }
        status.stringValue = text
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            try agent.setEnabled(launchAtLogin.state == .on)
        } catch {
            launchAtLogin.state = agent.isEnabled ? .on : .off
            status.stringValue = "Could not update launch agent: \(error.localizedDescription)"
        }
    }
}
