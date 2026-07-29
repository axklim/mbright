import ArgumentParser
import MBrightCore

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

func makeController() throws -> BrightnessController {
    BrightnessController(
        enumerator: SystemDisplayEnumerator(),
        backend: try DisplayServicesBackend()
    )
}
