import AppKit
import CoreGraphics
import MBrightCore
import MBrightIPC

/// Owns the status item and its menu. All state lives on the main actor.
@MainActor
public final class StatusMenuController: NSObject, NSMenuDelegate {
    private let connection: DaemonConnection
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let settings: SettingsWindowController
    private let debug = DebugLog(url: DebugLog.resolve(name: "mbright-menubar"))

    private var rows: [DisplayRow] = []
    private var lastFailure: String?
    private var isMenuOpen = false
    private var sliderViews: [CGDirectDisplayID: DisplaySliderView] = [:]
    /// One request in flight per display; the newest value waits its turn.
    /// A fast drag produces dozens of values a second, and sending every
    /// one would queue behind the daemon rather than track the thumb.
    private var inFlight: Set<CGDirectDisplayID> = []
    private var queued: [CGDirectDisplayID: Int] = [:]

    public init(connection: DaemonConnection) {
        self.connection = connection
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.settings = SettingsWindowController(connection: connection)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "sun.max", accessibilityDescription: "Brightness")
            button.image?.isTemplate = true
        }
        menu.delegate = self
        statusItem.menu = menu

        connection.onEvent = { [weak self] event in
            guard let self else { return }
            switch event {
            case .displaysChanged:
                debug.log("event displaysChanged")
                refresh()
            case let .brightnessChanged(id, percent):
                debug.log("event brightnessChanged \(id) \(percent)%")
                brightnessChanged(id: id, percent: percent)
            case let .configChanged(config):
                if config.debug { debug.setEnabled(true) }
                debug.log("event configChanged \(config)")
                if !config.debug { debug.setEnabled(false) }
            }
        }
        connection.onDisconnect = { [weak self] reason in
            self?.debug.log("disconnected: \(reason)")
            self?.lastFailure = reason
        }
        // The debug setting lives in the daemon; ask on every connect so a
        // daemon restarted with a different config is followed too.
        connection.onConnect = { [weak self] in
            guard let self else { return }
            connection.send(.config) { [weak self] response in
                guard let self, case let .config(status) = response else { return }
                debug.setEnabled(status.config.debug)
                debug.log("mbright-menubar \(Version.current) connected, pid \(getpid()), config \(status.config)")
            }
        }
        connection.subscribe()
        refresh()
    }

    // MARK: - NSMenuDelegate

    public func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
        debug.log("menu opening with cached rows \(Self.describe(rows))")
        rebuild()
        refresh()
    }

    public func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
        debug.log("menu closed")
    }

    // MARK: - Data

    private func refresh() {
        connection.send(.readings) { [weak self] response in
            guard let self else { return }
            switch response {
            case let .readings(readings):
                rows = MenuModel.rows(from: readings)
                lastFailure = nil
                debug.log("readings \(Self.describe(rows))")
            case let .failure(error):
                rows = []
                lastFailure = error.description
                debug.log("readings failed: \(error)")
            default:
                rows = []
                lastFailure = "unexpected reply from mbrightd"
                debug.log("readings: unexpected reply")
            }
            if isMenuOpen { rebuild() }
        }
    }

    /// Pushed by the daemon for every write, including this app's own; the
    /// slider view ignores updates while the thumb is being dragged.
    private func brightnessChanged(id: CGDirectDisplayID, percent: Int) {
        rows = rows.map { row in
            guard row.id == id, row.percent != nil else { return row }
            return DisplayRow(id: row.id, name: row.name, percent: percent, detail: nil)
        }
        sliderViews[id]?.update(percent: percent)
    }

    private func setBrightness(_ percent: Int, for id: CGDirectDisplayID) {
        guard !inFlight.contains(id) else {
            queued[id] = percent
            return
        }
        inFlight.insert(id)
        debug.log("set \(id) \(percent)%")
        connection.send(.set(percent: percent, target: .id(id))) { [weak self] response in
            guard let self else { return }
            inFlight.remove(id)
            if case let .failure(error) = response {
                lastFailure = error.description
                debug.log("set \(id) failed: \(error)")
            }
            if let next = queued.removeValue(forKey: id) {
                setBrightness(next, for: id)
            }
        }
    }

    // MARK: - Menu

    /// Rebuilding while the menu is open is fine: NSMenu re-lays out live.
    /// Slider views are replaced only when the set of displays changed, so
    /// a drag in progress is never interrupted by a refresh.
    private func rebuild() {
        let rowIDs = rows.map(\.id)
        if Set(sliderViews.keys) == Set(rowIDs), !rows.isEmpty {
            debug.log("rebuild: reusing slider views for \(rowIDs)")
            for row in rows {
                if let percent = row.percent { sliderViews[row.id]?.update(percent: percent) }
            }
            return
        }

        debug.log("rebuild: recreating views, had \(sliderViews.keys.sorted()), rows \(Self.describe(rows))")
        menu.removeAllItems()
        sliderViews = [:]

        if let failure = lastFailure, rows.isEmpty {
            menu.addItem(disabled(failure))
            menu.addItem(withTitle: "Retry", action: #selector(retry), keyEquivalent: "").target = self
        } else if rows.isEmpty {
            menu.addItem(disabled("No displays"))
        } else {
            for row in rows {
                let item = NSMenuItem()
                let view = DisplaySliderView(row: row) { [weak self] percent in
                    self?.setBrightness(percent, for: row.id)
                }
                item.view = view
                sliderViews[row.id] = view
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        menu.addItem(withTitle: "About mbright", action: #selector(showAbout), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit mbright", action: #selector(quit), keyEquivalent: "q").target = self
    }

    private static func describe(_ rows: [DisplayRow]) -> String {
        "[" + rows.map { row in
            "\(row.name) (\(row.id)) " + (row.percent.map { "\($0)%" } ?? "no slider: \(row.detail ?? "")")
        }.joined(separator: ", ") + "]"
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    // MARK: - Actions

    @objc private func retry() {
        refresh()
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let credits = NSAttributedString(
            string: "Brightness control for macOS displays that ignore DDC/CI.\nhttps://github.com/axklim/mbright",
            attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)])
        var options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: "mbright",
            .applicationVersion: Version.current,
            .version: "",
            .credits: credits,
        ]
        // A bare executable has no bundle icon; without this the panel
        // shows a generic folder.
        if let icon = NSImage(systemSymbolName: "sun.max", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 64, weight: .regular)) {
            options[.applicationIcon] = icon
        }
        NSApp.orderFrontStandardAboutPanel(options: options)
    }

    @objc private func showSettings() {
        settings.show()
    }

    /// Stops the daemon too; a stuck one must not keep the app open, hence
    /// the deadline.
    @objc private func quit() {
        connection.shutdownDaemon { NSApp.terminate(nil) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { NSApp.terminate(nil) }
    }
}
