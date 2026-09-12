import AppKit
import Foundation
import MBrightCore
import MBrightIPC

/// A single-pane settings window. Every setting lives in the daemon's
/// config; this window only sends requests and shows what comes back.
@MainActor
final class SettingsWindowController {
    private let window: NSWindow
    private let launchAtLogin = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)
    private let syncButtons: [NSButton]
    private let syncHint = NSTextField(wrappingLabelWithString: "")
    private let shortcuts = NSTextField(wrappingLabelWithString: "")
    private let shortcutsHint = NSTextField(wrappingLabelWithString: "")
    private let accessibility = NSTextField(wrappingLabelWithString: "")
    private let openAccessibility = NSButton(title: "Open Accessibility Settings…", target: nil, action: nil)
    private let status = NSTextField(wrappingLabelWithString: "")
    private let stack = NSStackView()
    private let connection: DaemonConnection
    private var current = Config()
    private var configPath = "~/.config/mbright/config.json"

    /// Pushed by the hotkey listener; the window only shows it.
    var hotkeyState: HotkeyListener.State = .off {
        didSet { render() }
    }

    private static let syncTitles: [SyncMode: String] = [
        .off: "Off",
        .full: "Full",
        .relative: "Relative",
    ]

    private static let syncHints: [SyncMode: String] = [
        .off: "Each display is adjusted on its own.",
        .full: "Other displays are set to the main display's brightness.",
        .relative: "Other displays change by the same amount as the main display.",
    ]

    init(connection: DaemonConnection) {
        // Every stored property is assigned before `self` is touched.
        self.connection = connection
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 260),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false)
        // Radio buttons sharing an action in one superview are mutually
        // exclusive on their own; the tag says which mode each one is.
        syncButtons = SyncMode.allCases.enumerated().map { index, mode in
            let button = NSButton(radioButtonWithTitle: Self.syncTitles[mode] ?? mode.rawValue, target: nil, action: nil)
            button.tag = index
            return button
        }

        window.title = "mbright Settings"
        window.isReleasedWhenClosed = false

        launchAtLogin.target = self
        launchAtLogin.action = #selector(toggleLaunchAtLogin)
        for button in syncButtons {
            button.target = self
            button.action = #selector(selectSync(_:))
        }

        let syncLabel = NSTextField(labelWithString: "Sync with main display")
        syncHint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        syncHint.textColor = .secondaryLabelColor
        syncHint.preferredMaxLayoutWidth = 340
        // Seed with the longest possible text so fittingSize below measures
        // the window for its worst case; show()/apply overwrite these.
        syncHint.stringValue = Self.syncHints.values.max(by: { $0.count < $1.count }) ?? ""

        let radios = NSStackView(views: syncButtons)
        radios.orientation = .vertical
        radios.alignment = .leading
        radios.spacing = 4

        status.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        status.textColor = .secondaryLabelColor
        status.preferredMaxLayoutWidth = 340
        status.stringValue = "Launch at login takes effect at the next login."

        let shortcutsLabel = NSTextField(labelWithString: "Keyboard shortcuts")
        shortcuts.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        shortcuts.preferredMaxLayoutWidth = 340
        for hint in [shortcutsHint, accessibility] {
            hint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            hint.textColor = .secondaryLabelColor
            hint.preferredMaxLayoutWidth = 340
        }
        accessibility.stringValue = "Shortcuts need Accessibility access for mbright. Allow it, then they start working."
        openAccessibility.target = self
        openAccessibility.action = #selector(showAccessibilitySettings)
        openAccessibility.controlSize = .small

        let version = NSTextField(labelWithString: "mbright \(Version.current)")
        version.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        version.textColor = .tertiaryLabelColor

        for view in [
            launchAtLogin, syncLabel, radios, syncHint,
            shortcutsLabel, shortcuts, shortcutsHint, accessibility, openAccessibility,
            status, version,
        ] {
            stack.addArrangedSubview(view)
        }
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.setCustomSpacing(16, after: launchAtLogin)
        stack.setCustomSpacing(16, after: syncHint)
        stack.setCustomSpacing(16, after: openAccessibility)
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            stack.widthAnchor.constraint(equalToConstant: 380),
        ])
        window.contentView = content
        render()
    }

    func show() {
        setEnabled(false)
        status.stringValue = "Launch at login takes effect at the next login."
        connection.send(.config) { [weak self] response in
            self?.apply(response)
        }
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func toggleLaunchAtLogin() {
        var config = current
        config.login = launchAtLogin.state == .on
        send(config)
    }

    @objc private func selectSync(_ sender: NSButton) {
        var config = current
        config.sync = SyncMode.allCases[sender.tag]
        send(config)
    }

    @objc private func showAccessibilitySettings() {
        HotkeyListener.openAccessibilitySettings()
    }

    /// Only the changed key differs from what the daemon last reported, so
    /// the other keys survive a change made elsewhere in the meantime.
    private func send(_ config: Config) {
        setEnabled(false)
        connection.send(.setConfig(config)) { [weak self] response in
            self?.apply(response)
        }
    }

    private func setEnabled(_ enabled: Bool) {
        launchAtLogin.isEnabled = enabled
        for button in syncButtons { button.isEnabled = enabled }
    }

    /// The controls always show what the daemon holds, so a failed change
    /// snaps back.
    private func apply(_ response: Response) {
        setEnabled(true)
        switch response {
        case let .config(configStatus):
            current = configStatus.config
            configPath = (configStatus.path as NSString).abbreviatingWithTildeInPath
            status.stringValue = "Launch at login takes effect at the next login."
        case let .failure(error):
            status.stringValue = "\(error)"
        default:
            status.stringValue = "Unexpected reply from mbrightd."
        }
        launchAtLogin.state = current.login ? .on : .off
        for (index, mode) in SyncMode.allCases.enumerated() {
            syncButtons[index].state = mode == current.sync ? .on : .off
        }
        syncHint.stringValue = Self.syncHints[current.sync] ?? ""
        render()
    }

    /// The shortcut section follows the daemon's config and the
    /// listener's state; the window grows and shrinks with it.
    private func render() {
        shortcuts.stringValue = current.hotkeys.isEmpty
            ? "Off"
            : current.hotkeys.map(\.description).joined(separator: "\n")
        shortcutsHint.stringValue = "Edit hotkeys in \(configPath), then run 'mbright config reload'."
        let needsAccess = hotkeyState == .needsAccessibility
        accessibility.isHidden = !needsAccess
        openAccessibility.isHidden = !needsAccess
        window.setContentSize(stack.fittingSize)
    }
}
