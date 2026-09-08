/// User settings. Owned by the daemon; clients only see it through the
/// wire. Missing keys decode to their defaults so an older file stays
/// valid when a key is added.
public struct Config: Equatable, Sendable, Codable {
    public var login: Bool
    public var ui: Bool

    public init(login: Bool = false, ui: Bool = true) {
        self.login = login
        self.ui = ui
    }

    private enum CodingKeys: String, CodingKey { case login, ui }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        login = try container.decodeIfPresent(Bool.self, forKey: .login) ?? false
        ui = try container.decodeIfPresent(Bool.self, forKey: .ui) ?? true
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
