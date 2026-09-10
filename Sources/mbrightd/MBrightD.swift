import AppKit
import ArgumentParser
import Foundation
import MBrightCore
import MBrightDaemon
import MBrightIPC

@main
struct MBrightD: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mbrightd",
        abstract: "Brightness daemon for the mbright CLI and menu bar app.",
        discussion: """
            Listens on $XDG_RUNTIME_DIR/mbright/mbrightd.sock, or the per-user temp dir \
            when XDG_RUNTIME_DIR is unset. Reads $XDG_CONFIG_HOME/mbright/config.json and \
            keeps the login LaunchAgent in step with it. Runs in the foreground until \
            SIGTERM or 'mbright daemon stop'.
            """,
        version: Version.current
    )

    func run() throws {
        let path = SocketPath.resolve()
        guard !DaemonProbe.isRunning(at: path) else {
            throw ValidationError("mbrightd is already running on \(path).")
        }

        let enumerator = SystemDisplayEnumerator()
        let controller = BrightnessController(enumerator: enumerator, backend: try DisplayServicesBackend())
        let handler = RequestHandler(controller: controller)

        // Everything below runs on the main thread: `run()` is invoked from
        // `main`, and NSApplication.run keeps it there.
        MainActor.assumeIsolated {
            let debug = DebugLog(url: DebugLog.resolve(name: "mbrightd"))
            let executable = Bundle.main.executableURL?.resolvingSymlinksInPath().path ?? CommandLine.arguments[0]
            let settings = SettingsHandler(
                file: ConfigFile(url: ConfigFile.resolve()),
                executable: executable,
                agentURL: LaunchAgent.defaultFileURL,
                bundle: InstalledBundle(daemonExecutable: executable),
                environment: ProcessInfo.processInfo.environment,
                log: { FileHandle.standardError.write(Data("\($0)\n".utf8)) })
            settings.start()
            debug.setEnabled(settings.config.debug)
            debug.log("mbrightd \(Version.current) starting, pid \(getpid()), socket \(path), config \(settings.config)")

            let sync = BrightnessSync(controller: controller, debug: { debug.log($0) }) {
                FileHandle.standardError.write(Data("\($0)\n".utf8))
                debug.log($0)
            }

            let server = LineServer(path: path, queue: .main) { request in
                if request == .shutdown {
                    debug.log("request shutdown")
                    // Reply first; the server writes it before this runs.
                    DispatchQueue.main.async { Shutdown.perform() }
                    return .ok
                }
                return MainActor.assumeIsolated {
                    let response = settings.handle(request) ?? sync.handle(request) ?? handler.handle(request)
                    debug.log("request \(Describe.request(request)) -> \(Describe.response(response))")
                    return response
                }
            }
            Shutdown.action = { debug.log("exiting"); server.stop(); Darwin.exit(0) }

            settings.onChange = { config in
                // Turning off is logged before the file closes.
                if config.debug { debug.setEnabled(true) }
                debug.log("config changed: \(config)")
                if !config.debug { debug.setEnabled(false) }
                sync.setMode(config.sync)
                server.broadcast(.configChanged(config))
            }
            sync.setMode(settings.config.sync)

            let observer = DisplayServicesBrightnessObserver(log: { debug.log($0) }) { id, value in
                DispatchQueue.main.async {
                    let percent = Percent.fromDevice(value)
                    debug.log("notification \(id) value \(value) -> \(percent)%")
                    server.broadcast(.brightnessChanged(id: id, percent: percent))
                    MainActor.assumeIsolated { sync.brightnessChanged(id: id, percent: percent) }
                }
            }
            let observeAll: @MainActor () -> Void = {
                observer.observe((try? enumerator.onlineDisplays())?.map(\.id) ?? [])
            }
            let logReadings: @MainActor (String) -> Void = { tag in
                guard debug.isEnabled else { return }
                do {
                    let readings = try controller.readings()
                    debug.log("\(tag): \(Describe.readings(readings))")
                } catch {
                    debug.log("\(tag): readings failed: \(error)")
                }
            }

            DisplayWatcher.start(log: { debug.log($0) }) {
                debug.log("displays settled after \(DisplayWatcher.settleDelay)s")
                logReadings("displays")
                observeAll()
                sync.displaysChanged()
                server.broadcast(.displaysChanged)
            }
            SignalHandler.install { debug.log("signal"); Shutdown.perform() }

            do {
                try server.start()
            } catch {
                FileHandle.standardError.write(Data("Error: \(error)\n".utf8))
                debug.log("could not start server: \(error)")
                Darwin.exit(1)
            }
            logReadings("start")
            observeAll()

            // A prohibited-policy NSApplication has no Dock icon or UI, but
            // keeps NSScreen.screens current across hotplugs and services
            // the main dispatch queue the socket sources run on.
            let app = NSApplication.shared
            app.setActivationPolicy(.prohibited)
            app.run()
        }
    }
}

enum DaemonProbe {
    static func isRunning(at path: String) -> Bool {
        guard let client = try? BlockingClient(path: path) else { return false }
        if case .version = try? client.request(.version) { return true }
        return false
    }
}

/// Coalesces the burst of CoreGraphics reconfiguration callbacks that one
/// plug or unplug produces into a single notification.
@MainActor
final class DisplayWatcher {
    static var shared: DisplayWatcher?
    static let settleDelay: TimeInterval = 0.3

    private let onChange: @MainActor () -> Void
    private let log: @MainActor (String) -> Void
    private var pending: DispatchWorkItem?

    private init(log: @escaping @MainActor (String) -> Void, onChange: @escaping @MainActor () -> Void) {
        self.log = log
        self.onChange = onChange
    }

    static func start(log: @escaping @MainActor (String) -> Void, onChange: @escaping @MainActor () -> Void) {
        shared = DisplayWatcher(log: log, onChange: onChange)
        CGDisplayRegisterReconfigurationCallback({ id, flags, _ in
            MainActor.assumeIsolated { DisplayWatcher.shared?.schedule(id: id, flags: flags) }
        }, nil)
    }

    private func schedule(id: CGDirectDisplayID, flags: CGDisplayChangeSummaryFlags) {
        log("reconfiguration callback: display \(id) flags 0x\(String(flags.rawValue, radix: 16))")
        pending?.cancel()
        let item = DispatchWorkItem { [onChange] in
            MainActor.assumeIsolated { onChange() }
        }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDelay, execute: item)
    }
}

/// One exit path for signals and the `shutdown` request: stop the server,
/// which unlinks the socket, then exit.
enum Shutdown {
    nonisolated(unsafe) static var action: (@Sendable () -> Void)?
    static func perform() { action?() }
}

/// SIGTERM/SIGINT/SIGHUP go through `Shutdown` so the socket file is
/// removed on the way out and the next start finds no stale one.
enum SignalHandler {
    nonisolated(unsafe) private static var sources: [DispatchSourceSignal] = []

    static func install(_ handler: @escaping @Sendable () -> Void) {
        for signalNumber in [SIGTERM, SIGINT, SIGHUP] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler(handler: handler)
            source.resume()
            sources.append(source)
        }
    }
}
