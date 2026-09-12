import MBrightCore
import MBrightIPC

/// One-line forms of wire messages for the debug log.
enum Describe {
    static func request(_ request: Request) -> String {
        switch request {
        case .readings: return "readings"
        case let .get(target): return "get \(self.target(target))"
        case let .set(percent, target): return "set \(percent)% \(self.target(target))"
        case let .adjust(delta, target): return "adjust \(delta >= 0 ? "+" : "")\(delta) \(self.target(target))"
        case .subscribe: return "subscribe"
        case .version: return "version"
        case .shutdown: return "shutdown"
        case .config: return "config"
        case let .setConfig(config): return "setConfig \(config)"
        case .reloadConfig: return "reloadConfig"
        case .writeConfig: return "writeConfig"
        case .updateConfig: return "updateConfig"
        }
    }

    static func response(_ response: Response) -> String {
        switch response {
        case let .readings(readings): return self.readings(readings)
        case let .percent(percent): return "\(percent)%"
        case .ok: return "ok"
        case let .version(version): return "version \(version)"
        case let .config(status): return "config \(status.config)"
        case let .failure(error): return "failure: \(error)"
        }
    }

    static func readings(_ readings: [DisplayReading]) -> String {
        readings.map { reading in
            let state: String
            switch reading.state {
            case let .percent(percent): state = "\(percent)%"
            case .unsupported: state = "unsupported"
            case let .failed(message): state = "failed(\(message))"
            }
            return "\(reading.display.name) (\(reading.display.id)\(reading.display.isMain ? "*" : "")) \(state)"
        }.joined(separator: ", ")
    }

    static func target(_ target: Target) -> String {
        switch target {
        case .all: return "all"
        case .main: return "main"
        case .secondary: return "secondary"
        case let .selector(selector): return "'\(selector)'"
        case let .id(id): return "id \(id)"
        }
    }
}
