import ArgumentParser
import Foundation
import MBrightCore

struct ListCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "Show every online display and its brightness."
    )

    func run() throws {
        let readings = try makeController().readings()
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
                FileHandle.standardError.write(Data("\(failure)\n".utf8))
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

    func run() throws {
        if target.all {
            throw ValidationError("get does not support --all; use 'mbright list'.")
        }
        print(try makeController().get(try target.resolvedTarget()))
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

    func validate() throws {
        guard (0...100).contains(percent) else {
            throw ValidationError("Brightness must be between 0 and 100.")
        }
    }

    func run() throws {
        try makeController().set(percent: percent, target: try target.resolvedTarget())
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

    func validate() throws {
        guard (0...100).contains(delta) else {
            throw ValidationError("Delta must be between 0 and 100.")
        }
    }

    func run() throws {
        try makeController().adjust(delta: delta, target: try target.resolvedTarget())
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

    func validate() throws {
        guard (0...100).contains(delta) else {
            throw ValidationError("Delta must be between 0 and 100.")
        }
    }

    func run() throws {
        try makeController().adjust(delta: -delta, target: try target.resolvedTarget())
    }
}
