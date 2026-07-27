/// Converts between the CLI's integer percent (0-100) and the unit interval
/// (0.0-1.0) that DisplayServices uses. All rounding lives here.
public enum Percent {
    public static func toDevice(_ percent: Int) -> Float {
        Float(percent) / 100.0
    }

    public static func fromDevice(_ value: Float) -> Int {
        Int((value * 100).rounded())
    }

    public static func clamp(_ percent: Int) -> Int {
        min(100, max(0, percent))
    }
}
