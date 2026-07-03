import Foundation
import CoreLocation

struct SpeedSample: Identifiable {
    let id: Int
    let t: Double        // seconds since ride start
    let speed: Double    // m/s
}

struct RideAnalysis {
    let maxLeanDegrees: Double
    let maxAccelG: Double
    let maxBrakeG: Double
}

enum RideMath {

    static func speedSamples(_ points: [RidePoint]) -> [SpeedSample] {
        guard let start = points.first?.timestamp else { return [] }
        return points.enumerated().map { i, p in
            SpeedSample(id: i, t: p.timestamp.timeIntervalSince(start), speed: p.speed)
        }
    }

    /// Longitudinal G and lean angle derived from GPS (speed delta + course rate),
    /// so it works no matter how the phone is mounted or pocketed.
    static func analysis(_ points: [RidePoint]) -> RideAnalysis {
        var maxLean = 0.0, maxAccel = 0.0, maxBrake = 0.0
        guard points.count >= 2 else {
            return RideAnalysis(maxLeanDegrees: 0, maxAccelG: 0, maxBrakeG: 0)
        }
        for i in 0..<(points.count - 1) {
            let a = points[i], b = points[i + 1]
            let dt = b.timestamp.timeIntervalSince(a.timestamp)
            guard dt > 0.2 else { continue }

            // Longitudinal G from speed change (filter GPS spikes above 1.6 g)
            let g = (b.speed - a.speed) / dt / 9.81
            if abs(g) < 1.6 {
                if g > 0 { maxAccel = max(maxAccel, g) }
                else { maxBrake = max(maxBrake, -g) }
            }

            // Lean from turn rate: lean = atan(v * omega / g)
            if a.course >= 0, b.course >= 0, b.speed > 3 {
                var d = b.course - a.course
                if d > 180 { d -= 360 }
                if d < -180 { d += 360 }
                let omega = abs(d) * .pi / 180 / dt
                let lean = atan(b.speed * omega / 9.81) * 180 / .pi
                if lean < 65 { maxLean = max(maxLean, lean) }
            }
        }
        return RideAnalysis(maxLeanDegrees: maxLean, maxAccelG: maxAccel, maxBrakeG: maxBrake)
    }
}
