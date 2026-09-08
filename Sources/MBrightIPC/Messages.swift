import CoreGraphics
import MBrightCore

/// Wire messages between clients and `mbrightd`. Both ends are Swift, so the
/// synthesized `Codable` encoding is the contract; there is no hand-written
/// JSON schema to keep in sync.
public enum Request: Equatable, Sendable, Codable {
    case readings
    case get(target: Target)
    case set(percent: Int, target: Target)
    case adjust(delta: Int, target: Target)
    /// Marks the connection as wanting `Event`s. Handled by the server, not
    /// the request handler.
    case subscribe
    case version
    /// Asks the daemon to exit after replying. Handled by the daemon
    /// executable, not the request handler.
    case shutdown
    /// Config requests are handled by the daemon executable, not the
    /// request handler. All four reply with `.config(ConfigStatus)`.
    case config
    case setConfig(Config)
    case reloadConfig
    /// Creates the file from the current config if none exists.
    case writeConfig
}

public enum Response: Equatable, Sendable, Codable {
    case readings([DisplayReading])
    case percent(Int)
    case ok
    case version(String)
    case config(ConfigStatus)
    case failure(MBrightError)
}

/// Pushed by the daemon to subscribed connections, outside any request.
public enum Event: Equatable, Sendable, Codable {
    case displaysChanged
    /// A display's brightness changed, by anyone: a CLI write, System
    /// Settings, a keyboard key, or the display's own auto-brightness.
    case brightnessChanged(id: CGDirectDisplayID, percent: Int)
}

public struct ClientMessage: Equatable, Sendable, Codable {
    public let id: Int
    public let request: Request

    public init(id: Int, request: Request) {
        self.id = id
        self.request = request
    }
}

public enum ServerMessage: Equatable, Sendable, Codable {
    case reply(id: Int, response: Response)
    case event(Event)
}
