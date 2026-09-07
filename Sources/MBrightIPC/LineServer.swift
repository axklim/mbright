import Foundation

/// Accepts client connections on a Unix socket and answers each
/// `ClientMessage` with one `ServerMessage.reply`. Connections that send
/// `subscribe` also receive every `broadcast` event.
///
/// Every piece of mutable state is touched only on `queue`; the
/// `@unchecked Sendable` is that invariant, not an escape hatch.
public final class LineServer: @unchecked Sendable {
    public typealias Handler = @Sendable (Request) -> Response

    private final class Connection {
        let fd: Int32
        let source: DispatchSourceRead
        var buffer = LineBuffer()
        var subscribed = false

        init(fd: Int32, source: DispatchSourceRead) {
            self.fd = fd
            self.source = source
        }
    }

    public let path: String
    private let queue: DispatchQueue
    private let handler: Handler
    private var listener: DispatchSourceRead?
    private var connections: [Int32: Connection] = [:]
    /// Invoked on `queue` whenever a connection opens or closes.
    public var onConnectionCountChanged: (@Sendable (Int) -> Void)?

    public init(path: String, queue: DispatchQueue, handler: @escaping Handler) {
        self.path = path
        self.queue = queue
        self.handler = handler
    }

    public var connectionCount: Int { connections.count }

    public func start() throws {
        let fd = try UnixSocket.listen(path: path)
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptPending(on: fd) }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        listener = source
    }

    public func stop() {
        for connection in connections.values { drop(connection) }
        listener?.cancel()
        listener = nil
        unlink(path)
    }

    public func broadcast(_ event: Event) {
        guard let data = try? LineCodec.encode(ServerMessage.event(event)) else { return }
        for connection in connections.values where connection.subscribed {
            send(data, to: connection)
        }
    }

    // MARK: - Internals

    private func acceptPending(on listenFD: Int32) {
        let fd = accept(listenFD, nil, nil)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        let connection = Connection(fd: fd, source: source)
        source.setEventHandler { [weak self] in self?.readPending(from: connection) }
        source.setCancelHandler {
            close(fd)
        }
        connections[fd] = connection
        source.resume()
        onConnectionCountChanged?(connections.count)
    }

    private func readPending(from connection: Connection) {
        guard let data = try? UnixSocket.read(connection.fd), !data.isEmpty else {
            drop(connection)
            return
        }
        for line in connection.buffer.append(data) {
            guard let message = try? LineCodec.decode(ClientMessage.self, from: line) else {
                // A client that cannot frame a request is broken; cutting it
                // off is clearer than guessing which id to answer.
                drop(connection)
                return
            }
            let response: Response
            if message.request == .subscribe {
                connection.subscribed = true
                response = .ok
            } else {
                response = handler(message.request)
            }
            guard let reply = try? LineCodec.encode(ServerMessage.reply(id: message.id, response: response)) else {
                continue
            }
            send(reply, to: connection)
        }
    }

    private func send(_ data: Data, to connection: Connection) {
        do {
            try UnixSocket.writeAll(connection.fd, data)
        } catch {
            drop(connection)
        }
    }

    private func drop(_ connection: Connection) {
        guard connections.removeValue(forKey: connection.fd) != nil else { return }
        connection.source.cancel()
        onConnectionCountChanged?(connections.count)
    }
}
