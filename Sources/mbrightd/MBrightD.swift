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
            let executable = Bundle.main.executableURL?.resolvingSymlinksInPath().path ?? CommandLine.arguments[0]
            let settings = SettingsHandler(
                file: ConfigFile(url: ConfigFile.resolve()),
                executable: executable,
                agentURL: LaunchAgent.defaultFileURL,
                bundle: InstalledBundle(daemonExecutable: executable),
                environment: ProcessInfo.processInfo.environment,
                log: { FileHandle.standardError.write(Data("\($0)\n".utf8)) })
            settings.start()

            let server = LineServer(path: path, queue: .main) { request in
                if request == .shutdown {
                    // Reply first; the server writes it before this runs.
                    DispatchQueue.main.async { Shutdown.perform() }
                    return .ok
                }
                if let response = MainActor.assumeIsolated({ settings.handle(request) }) { return response }
                return handler.handle(request)
            }
            Shutdown.action = { server.stop(); Darwin.exit(0) }

            let observer = DisplayServicesBrightnessObserver { id, value in
                DispatchQueue.main.async {
                    server.broadcast(.brightnessChanged(id: id, percent: Percent.fromDevice(value)))
                }
            }
            let observeAll: @MainActor () -> Void = {
                observer.observe((try? enumerator.onlineDisplays())?.map(\.id) ?? [])
            }

            DisplayWatcher.start {
                observeAll()
                server.broadcast(.displaysChanged)
            }
            SignalHandler.install { Shutdown.perform() }

            do {
                try server.start()
            } catch {
                FileHandle.standardError.write(Data("Error: \(error)\n".utf8))
                Darwin.exit(1)
            }
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
    private static let settleDelay: TimeInterval = 0.3

    private let onChange: @MainActor () -> Void
    private var pending: DispatchWorkItem?

    private init(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
    }

    static func start(onChange: @escaping @MainActor () -> Void) {
        shared = DisplayWatcher(onChange: onChange)
        CGDisplayRegisterReconfigurationCallback({ _, _, _ in
            MainActor.assumeIsolated { DisplayWatcher.shared?.schedule() }
        }, nil)
    }

    private func schedule() {
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
