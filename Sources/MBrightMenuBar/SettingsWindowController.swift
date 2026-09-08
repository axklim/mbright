import AppKit
import Foundation
import MBrightCore
import MBrightIPC

/// A single-pane settings window. The one setting is Launch at login,
/// which lives in the daemon's config; this window only sends requests
/// and shows what comes back.
@MainActor
final class SettingsWindowController {
    private let window: NSWindow
    private let launchAtLogin = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)
    private let status = NSTextField(wrappingLabelWithString: "")
    private let connection: DaemonConnection
    private var current = Config()

    init(connection: DaemonConnection) {
        self.connection = connection

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
        launchAtLogin.isEnabled = false
        status.stringValue = "Takes effect at the next login."
        connection.send(.config) { [weak self] response in
            self?.apply(response)
        }
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func toggleLaunchAtLogin() {
        launchAtLogin.isEnabled = false
        let wanted = launchAtLogin.state == .on
        connection.send(.setConfig(Config(login: wanted, ui: true))) { [weak self] response in
            self?.apply(response)
        }
    }

    /// The checkbox always shows what the daemon holds, so a failed change
    /// snaps it back.
    private func apply(_ response: Response) {
        launchAtLogin.isEnabled = true
        switch response {
        case let .config(configStatus):
            current = configStatus.config
            status.stringValue = "Takes effect at the next login."
        case let .failure(error):
            status.stringValue = "\(error)"
        default:
            status.stringValue = "Unexpected reply from mbrightd."
        }
        launchAtLogin.state = current.login ? .on : .off
    }
}
