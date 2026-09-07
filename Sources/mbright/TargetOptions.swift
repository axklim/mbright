import ArgumentParser
import Foundation
import MBrightCore
import MBrightIPC

struct TargetOptions: ParsableArguments {
    @Option(name: [.customShort("d"), .customLong("display")],
            help: "Display index, ID, or name substring (e.g. studio).")
    var display: String?

    @Flag(name: .long, help: "Apply to every online display.")
    var all = false

    func validate() throws {
        _ = try resolvedTarget()
    }

    func resolvedTarget() throws -> Target {
        do {
            return try Target.resolve(display: display, all: all)
        } catch MBrightError.conflictingTargetFlags {
            throw ValidationError("--display and --all are mutually exclusive.")
        }
    }
}

struct DaemonOptions: ParsableArguments {
    @Flag(name: .customLong("daemon-autostart"),
          help: "Start mbrightd if it is not running. Without this, a missing daemon is an error.")
    var daemonAutostart = false
}

/// Sends one request to `mbrightd` and turns a `.failure` reply back into
/// the thrown `MBrightError`, so the CLI reports exactly what the
/// controller would have thrown in-process.
func perform(_ request: Request, autostart: Bool) throws -> Response {
    let client = BlockingClient(fd: try DaemonLauncher.connect(spawnIfNeeded: autostart))
    let response = try client.request(request)
    if case let .failure(error) = response { throw error }
    return response
}

func unexpected(_ response: Response) -> MBrightError {
    .daemonFailure("unexpected reply: \(response)")
}
