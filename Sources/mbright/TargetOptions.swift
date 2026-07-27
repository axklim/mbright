import ArgumentParser
import MBrightCore

struct TargetOptions: ParsableArguments {
    @Option(name: [.customShort("d"), .customLong("display")],
            help: "Display index, ID, or name substring (e.g. studio).")
    var display: String?

    @Flag(name: .long, help: "Apply to every online display.")
    var all = false

    func resolvedTarget() throws -> Target {
        if all, display != nil {
            throw ValidationError("--display and --all are mutually exclusive.")
        }
        if all { return .all }
        if let display { return .selector(display) }
        return .main
    }
}

func makeController() throws -> BrightnessController {
    BrightnessController(
        enumerator: SystemDisplayEnumerator(),
        backend: try DisplayServicesBackend()
    )
}
