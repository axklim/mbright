import ArgumentParser
import Foundation
import MBrightCore
import MBrightIPC

struct ListCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "Show every online display and its brightness."
    )

    @OptionGroup var daemon: DaemonOptions

    func run() throws {
        let response = try perform(.readings, autostart: daemon.daemonAutostart)
        guard case let .readings(readings) = response else { throw unexpected(response) }
        print(ListTable.render(readings))

        // A display whose read failed must not look like a clean run: the
        // table still renders (the user sees every display), but a non-zero
        // exit and a stderr explanation make the partial failure visible.
        let failures = readings.compactMap { reading -> String? in
            guard case let .failed(message) = reading.state else { return nil }
            return "\(reading.display.name): \(message)"
        }
        guard failures.isEmpty else {
            for failure in failures {
                FileHandle.standardError.write(Data("Error: \(failure)\n".utf8))
            }
            throw ExitCode.failure
        }
    }
}

struct GetCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "get",
        abstract: "Print one display's brightness as a bare integer."
    )

    @OptionGroup var target: TargetOptions
    @OptionGroup var daemon: DaemonOptions

    func validate() throws {
        guard !target.all else {
            throw ValidationError("get does not support --all; use 'mbright list'.")
        }
    }

    func run() throws {
        let response = try perform(.get(target: try target.resolvedTarget()), autostart: daemon.daemonAutostart)
        guard case let .percent(percent) = response else { throw unexpected(response) }
        print(percent)
    }
}

struct SetCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "set",
        abstract: "Set brightness to an absolute percentage."
    )

    @Argument(help: "Brightness percentage, 0-100.")
    var percent: Int

    @OptionGroup var target: TargetOptions
    @OptionGroup var daemon: DaemonOptions

    func validate() throws {
        guard (0...100).contains(percent) else {
            throw ValidationError("Brightness must be between 0 and 100.")
        }
    }

    func run() throws {
        let response = try perform(.set(percent: percent, target: try target.resolvedTarget()),
                                   autostart: daemon.daemonAutostart)
        guard response == .ok else { throw unexpected(response) }
    }
}

struct UpCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "up",
        abstract: "Increase brightness, clamped at 100."
    )

    @Argument(help: "Percentage points to add.")
    var delta: Int = 10

    @OptionGroup var target: TargetOptions
    @OptionGroup var daemon: DaemonOptions

    func validate() throws {
        guard (0...100).contains(delta) else {
            throw ValidationError("Delta must be between 0 and 100.")
        }
    }

    func run() throws {
        let response = try perform(.adjust(delta: delta, target: try target.resolvedTarget()),
                                   autostart: daemon.daemonAutostart)
        guard response == .ok else { throw unexpected(response) }
    }
}

struct DownCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "down",
        abstract: "Decrease brightness, clamped at 0."
    )

    @Argument(help: "Percentage points to subtract.")
    var delta: Int = 10

    @OptionGroup var target: TargetOptions
    @OptionGroup var daemon: DaemonOptions

    func validate() throws {
        guard (0...100).contains(delta) else {
            throw ValidationError("Delta must be between 0 and 100.")
        }
    }

    func run() throws {
        let response = try perform(.adjust(delta: -delta, target: try target.resolvedTarget()),
                                   autostart: daemon.daemonAutostart)
        guard response == .ok else { throw unexpected(response) }
    }
}

struct DaemonCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "daemon",
        abstract: "Start, stop, or inspect mbrightd.",
        subcommands: [DaemonStart.self, DaemonStop.self, DaemonStatus.self]
    )
}

struct DaemonStart: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "start",
        abstract: "Start mbrightd in the background if it is not already running."
    )

    func run() throws {
        let path = SocketPath.resolve()
        if let fd = try? DaemonLauncher.connect(path: path, spawnIfNeeded: false) {
            let response = try BlockingClient(fd: fd).request(.version)
            if case let .version(version) = response {
                print("mbrightd \(version) is already running on \(path)")
                return
            }
        }
        let fd = try DaemonLauncher.connect(path: path, spawnIfNeeded: true)
        guard case let .version(version) = try BlockingClient(fd: fd).request(.version) else {
            throw MBrightError.daemonFailure("started mbrightd but it did not report a version")
        }
        print("mbrightd \(version) started on \(path)")
    }
}

struct DaemonStop: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stop",
        abstract: "Ask the running mbrightd to exit."
    )

    func run() throws {
        let response = try perform(.shutdown, autostart: false)
        guard response == .ok else { throw unexpected(response) }
        print("mbrightd stopped")
    }
}

struct DaemonStatus: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Report whether mbrightd is running. Exits 1 if it is not."
    )

    func run() throws {
        let path = SocketPath.resolve()
        do {
            let response = try perform(.version, autostart: false)
            guard case let .version(version) = response else { throw unexpected(response) }
            print("mbrightd \(version) is running on \(path)")
        } catch MBrightError.daemonNotRunning {
            print("mbrightd is not running (socket: \(path))")
            throw ExitCode.failure
        }
    }
}
