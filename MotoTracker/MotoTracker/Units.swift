import Foundation

enum Units {
    static func speedString(_ metersPerSecond: Double, metric: Bool) -> String {
        let v = metric ? metersPerSecond * 3.6 : metersPerSecond * 2.23694
        return String(format: "%.0f", v)
    }

    static func speedUnit(metric: Bool) -> String { metric ? "km/h" : "mph" }

    static func distanceString(_ meters: Double, metric: Bool) -> String {
        if metric {
            return meters >= 1000
                ? String(format: "%.2f km", meters / 1000)
                : String(format: "%.0f m", meters)
        } else {
            return String(format: "%.2f mi", meters / 1609.344)
        }
    }

    static func durationString(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }
}
