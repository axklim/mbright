import MBrightCore

/// Maps wire requests onto `BrightnessController`. Pure with respect to
/// I/O: everything hardware-shaped is behind the controller's protocols, so
/// this is tested against the same fakes as the controller.
public struct RequestHandler: Sendable {
    private let controller: BrightnessController
    private let version: String

    public init(controller: BrightnessController, version: String = Version.current) {
        self.controller = controller
        self.version = version
    }

    public func handle(_ request: Request) -> Response {
        do {
            switch request {
            case .readings:
                return .readings(try controller.readings())
            case let .get(target):
                return .percent(try controller.get(target))
            case let .set(percent, target):
                try controller.set(percent: percent, target: target)
                return .ok
            case let .adjust(delta, target):
                try controller.adjust(delta: delta, target: target)
                return .ok
            case .subscribe, .shutdown, .config, .setConfig, .reloadConfig, .writeConfig:
                return .ok
            case .version:
                return .version(version)
            }
        } catch let error as MBrightError {
            return .failure(error)
        } catch {
            return .failure(.daemonFailure("\(error)"))
        }
    }
}
