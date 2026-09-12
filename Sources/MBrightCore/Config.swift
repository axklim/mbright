/// How the other displays follow the main display.
public enum SyncMode: String, CaseIterable, Equatable, Sendable, Codable {
    case off
    /// Other displays are set to the main display's value.
    case full
    /// Other displays move by the same delta as the main display.
    case relative
}

/// User settings. Owned by the daemon; clients only see it through the
/// wire. Missing keys decode to their defaults so an older file stays
/// valid when a key is added.
public struct Config: Equatable, Sendable, Codable {
    public var login: Bool
    public var ui: Bool
    public var sync: SyncMode
    /// Writes a debug log under `$XDG_STATE_HOME/mbright/`.
    public var debug: Bool
    /// Global shortcuts the menu bar app listens for. Empty turns them off.
    public var hotkeys: [Hotkey]

    public init(
        login: Bool = false, ui: Bool = true, sync: SyncMode = .off, debug: Bool = false,
        hotkeys: [Hotkey] = Hotkey.defaults
    ) {
        self.login = login
        self.ui = ui
        self.sync = sync
        self.debug = debug
        self.hotkeys = hotkeys
    }

    private enum CodingKeys: String, CodingKey { case login, ui, sync, debug, hotkeys }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        login = try container.decodeIfPresent(Bool.self, forKey: .login) ?? false
        ui = try container.decodeIfPresent(Bool.self, forKey: .ui) ?? true
        sync = try container.decodeIfPresent(SyncMode.self, forKey: .sync) ?? .off
        debug = try container.decodeIfPresent(Bool.self, forKey: .debug) ?? false
        hotkeys = try container.decodeIfPresent([Hotkey].self, forKey: .hotkeys) ?? Hotkey.defaults
    }
}

/// What the daemon reports back for every config request.
public struct ConfigStatus: Equatable, Sendable, Codable {
    public let config: Config
    public let path: String
    public let onDisk: Bool

    public init(config: Config, path: String, onDisk: Bool) {
        self.config = config
        self.path = path
        self.onDisk = onDisk
    }
}
