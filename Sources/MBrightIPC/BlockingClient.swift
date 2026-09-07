import Foundation
import MBrightCore

/// Synchronous request/reply client for one-shot callers such as the CLI.
public final class BlockingClient {
    private let fd: Int32
    private var buffer = LineBuffer()
    private var nextID = 1

    /// Wraps an already-connected socket.
    public init(fd: Int32, receiveTimeoutSeconds: Int = 10) {
        self.fd = fd
        UnixSocket.setReceiveTimeout(fd, seconds: receiveTimeoutSeconds)
    }

    public convenience init(path: String) throws {
        self.init(fd: try UnixSocket.connect(path: path))
    }

    deinit { close(fd) }

    public func request(_ request: Request) throws -> Response {
        let id = nextID
        nextID += 1
        do {
            try UnixSocket.writeAll(fd, try LineCodec.encode(ClientMessage(id: id, request: request)))
        } catch {
            throw MBrightError.daemonUnavailable(reason: "\(error)")
        }

        while true {
            let data: Data
            do {
                data = try UnixSocket.read(fd)
            } catch {
                throw MBrightError.daemonUnavailable(reason: "\(error)")
            }
            guard !data.isEmpty else {
                throw MBrightError.daemonUnavailable(reason: "connection closed before a reply arrived")
            }
            for line in buffer.append(data) {
                let message: ServerMessage
                do {
                    message = try LineCodec.decode(ServerMessage.self, from: line)
                } catch {
                    throw MBrightError.daemonFailure("unreadable reply: \(error)")
                }
                if case let .reply(replyID, response) = message, replyID == id {
                    return response
                }
                // Events and stale replies are not for this call; keep reading.
            }
        }
    }
}

extension BlockingClient {
    /// Blocks until the daemon pushes an event. Only meaningful after a
    /// `.subscribe` request.
    public func waitForEvent() throws -> Event {
        while true {
            let data: Data
            do {
                data = try UnixSocket.read(fd)
            } catch {
                throw MBrightError.daemonUnavailable(reason: "\(error)")
            }
            guard !data.isEmpty else {
                throw MBrightError.daemonUnavailable(reason: "connection closed while waiting for an event")
            }
            for line in buffer.append(data) {
                if case let .event(event) = try LineCodec.decode(ServerMessage.self, from: line) {
                    return event
                }
            }
        }
    }
}
