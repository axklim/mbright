import Foundation
import MBrightCore

/// Main-thread client for long-lived callers such as the menu bar app.
/// Requests are asynchronous and events arrive on `onEvent`. If the daemon
/// goes away, the next `send` reconnects (spawning if necessary).
@MainActor
public final class DaemonConnection {
    public typealias Completion = @MainActor (Response) -> Void

    private let path: String
    private var fd: Int32 = -1
    private var source: DispatchSourceRead?
    private var buffer = LineBuffer()
    private var nextID = 1
    private var pending: [Int: Completion] = [:]
    private var subscribed = false
    /// Sends made while a connect is in flight wait here rather than each
    /// starting a connect of their own. A second socket would stay
    /// subscribed on the daemon with nobody reading it, and the daemon
    /// blocks once its receive buffer fills with broadcasts.
    private var waitingForConnect: [@MainActor (MBrightError?) -> Void] = []
    private var isConnecting = false

    public var onEvent: (@MainActor (Event) -> Void)?
    public var onDisconnect: (@MainActor (String) -> Void)?
    /// Runs after every successful connect, before the waiting sends.
    public var onConnect: (@MainActor () -> Void)?

    public init(path: String = SocketPath.resolve()) {
        self.path = path
    }

    public var isConnected: Bool { fd >= 0 }

    /// Sends a request; `completion` runs on the main actor with the reply,
    /// or with `.failure(.daemonUnavailable)` when the daemon cannot be
    /// reached.
    public func send(_ request: Request, completion: @escaping Completion) {
        ensureConnected { [self] connectionError in
            if let connectionError {
                completion(.failure(connectionError))
                return
            }
            let id = nextID
            nextID += 1
            pending[id] = completion
            do {
                try UnixSocket.writeAll(fd, try LineCodec.encode(ClientMessage(id: id, request: request)))
            } catch {
                pending.removeValue(forKey: id)
                disconnect(reason: "\(error)")
                completion(.failure(.daemonUnavailable(reason: "\(error)")))
            }
        }
    }

    /// Asks the daemon to exit. `completion` runs once it has replied or
    /// the socket closed. With no connection there is nothing to stop, and
    /// `send` would spawn a daemon only to tell it to exit, so this
    /// completes at once instead.
    public func shutdownDaemon(completion: @escaping @MainActor () -> Void) {
        guard isConnected else {
            completion()
            return
        }
        send(.shutdown) { _ in completion() }
    }

    /// Asks for events. The request itself is sent by the connect path, so
    /// it is re-sent automatically after every reconnect.
    public func subscribe() {
        subscribed = true
        ensureConnected { _ in }
    }

    // MARK: - Internals

    private func ensureConnected(_ then: @escaping @MainActor (MBrightError?) -> Void) {
        if isConnected {
            then(nil)
            return
        }
        waitingForConnect.append(then)
        guard !isConnecting else { return }
        isConnecting = true

        let path = path
        // Spawning and the connect-retry loop block for up to a few seconds;
        // that must not freeze the UI.
        Task.detached {
            let result: Result<Int32, MBrightError>
            do {
                result = .success(try DaemonLauncher.connect(path: path))
            } catch let error as MBrightError {
                result = .failure(error)
            } catch {
                result = .failure(.daemonUnavailable(reason: "\(error)"))
            }
            await MainActor.run {
                self.isConnecting = false
                switch result {
                case let .success(fd):
                    self.attach(fd)
                    self.onConnect?()
                    if self.subscribed {
                        let id = self.nextID
                        self.nextID += 1
                        self.pending[id] = { _ in }
                        try? UnixSocket.writeAll(fd, try LineCodec.encode(ClientMessage(id: id, request: .subscribe)))
                    }
                    self.resumeWaiters(nil)
                case let .failure(error):
                    self.resumeWaiters(error)
                }
            }
        }
    }

    private func resumeWaiters(_ error: MBrightError?) {
        let waiters = waitingForConnect
        waitingForConnect = []
        for waiter in waiters { waiter(error) }
    }

    private func attach(_ fd: Int32) {
        self.fd = fd
        buffer = LineBuffer()
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.readPending() }
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        self.source = source
    }

    private func readPending() {
        guard let data = try? UnixSocket.read(fd), !data.isEmpty else {
            disconnect(reason: "connection closed by mbrightd")
            return
        }
        for line in buffer.append(data) {
            guard let message = try? LineCodec.decode(ServerMessage.self, from: line) else { continue }
            switch message {
            case let .reply(id, response):
                pending.removeValue(forKey: id)?(response)
            case let .event(event):
                onEvent?(event)
            }
        }
    }

    private func disconnect(reason: String) {
        guard isConnected else { return }
        source?.cancel()
        source = nil
        fd = -1
        let waiting = pending
        pending = [:]
        for completion in waiting.values {
            completion(.failure(.daemonUnavailable(reason: reason)))
        }
        onDisconnect?(reason)
    }
}
