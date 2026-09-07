import Foundation

public enum SocketError: Error, Equatable, CustomStringConvertible {
    case pathTooLong(String)
    case posix(operation: String, code: Int32)

    public var description: String {
        switch self {
        case let .pathTooLong(path):
            return "Socket path is too long for sockaddr_un: \(path)"
        case let .posix(operation, code):
            return "\(operation) failed: \(String(cString: strerror(code))) (errno \(code))"
        }
    }
}

/// Thin wrappers over the BSD socket calls used by both ends.
enum UnixSocket {
    static func listen(path: String) throws -> Int32 {
        var address = try makeAddress(path)
        // The XDG layout puts the socket in an application subdirectory that
        // may not exist yet. 0700: a runtime dir must be private to the user.
        try FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketError.posix(operation: "socket", code: errno) }

        // A previous daemon that died without cleanup leaves the file behind.
        // Only remove it if nothing answers; a live daemon must not be evicted.
        if FileManager.default.fileExists(atPath: path), !isAlive(path: path) {
            unlink(path)
        }

        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0 else {
            let code = errno
            close(fd)
            throw SocketError.posix(operation: "bind", code: code)
        }
        guard Darwin.listen(fd, 16) == 0 else {
            let code = errno
            close(fd)
            unlink(path)
            throw SocketError.posix(operation: "listen", code: code)
        }
        return fd
    }

    static func connect(path: String) throws -> Int32 {
        var address = try makeAddress(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketError.posix(operation: "socket", code: errno) }
        suppressSIGPIPE(fd)

        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            let code = errno
            close(fd)
            throw SocketError.posix(operation: "connect", code: code)
        }
        return fd
    }

    static func isAlive(path: String) -> Bool {
        guard let fd = try? connect(path: path) else { return false }
        close(fd)
        return true
    }

    static func writeAll(_ fd: Int32, _ data: Data) throws {
        try data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            var offset = 0
            while offset < buffer.count {
                let written = Darwin.write(fd, buffer.baseAddress! + offset, buffer.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    throw SocketError.posix(operation: "write", code: errno)
                }
                offset += written
            }
        }
    }

    /// Reads whatever is available. Returns empty data on EOF.
    static func read(_ fd: Int32, max: Int = 64 * 1024) throws -> Data {
        var buffer = [UInt8](repeating: 0, count: max)
        while true {
            let count = Darwin.read(fd, &buffer, max)
            if count < 0 {
                if errno == EINTR { continue }
                throw SocketError.posix(operation: "read", code: errno)
            }
            return Data(buffer[0..<count])
        }
    }

    /// Turns a broken pipe into an `EPIPE` the caller can handle. Without
    /// it, writing to a peer that went away raises SIGPIPE, whose default
    /// action kills the process.
    static func suppressSIGPIPE(_ fd: Int32) {
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    }

    /// Marks a descriptor non-blocking. `MSG_DONTWAIT` is not honoured for
    /// AF_UNIX stream sockets on Darwin, so this is the only way a write
    /// can refuse instead of waiting.
    static func setNonBlocking(_ fd: Int32) {
        let flags = fcntl(fd, F_GETFL, 0)
        guard flags >= 0 else { return }
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
    }

    static func setReceiveTimeout(_ fd: Int32, seconds: Int) {
        var timeout = timeval(tv_sec: seconds, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    }

    private static func makeAddress(_ path: String) throws -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        let bytes = Array(path.utf8)
        guard bytes.count < capacity else { throw SocketError.pathTooLong(path) }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        return address
    }
}
