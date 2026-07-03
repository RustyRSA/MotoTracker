import Foundation
import CoreLocation

struct SpeedSample: Identifiable {
    let id: Int
    let t: Double        // seconds since ride start
    let speed: Double    // m/s
}

struct RideAnalysis {
    let maxLeanLeftDegrees: Double
    let maxLeanRightDegrees: Double
    let maxAccelG: Double
    let maxBrakeG: Double

    /// Larger of the two sides, for places that want a single figure.
    var maxLeanDegrees: Double { max(maxLeanLeftDegrees, maxLeanRightDegrees) }
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
        var maxLeanL = 0.0, maxLeanR = 0.0, maxAccel = 0.0, maxBrake = 0.0
        guard points.count >= 2 else {
            return RideAnalysis(maxLeanLeftDegrees: 0, maxLeanRightDegrees: 0,
                                maxAccelG: 0, maxBrakeG: 0)
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

            // Lean from turn rate: lean = atan(v * omega / g).
            // Course is degrees clockwise from north, so a positive wrapped
            // delta is a right-hand turn (right lean), negative is left.
            if a.course >= 0, b.course >= 0, b.speed > 3 {
                var d = b.course - a.course
                if d > 180 { d -= 360 }
                if d < -180 { d += 360 }
                let omega = abs(d) * .pi / 180 / dt
                let lean = atan(b.speed * omega / 9.81) * 180 / .pi
                if lean < 65 {
                    if d > 0 { maxLeanR = max(maxLeanR, lean) }
                    else if d < 0 { maxLeanL = max(maxLeanL, lean) }
                }
            }
        }
        return RideAnalysis(maxLeanLeftDegrees: maxLeanL, maxLeanRightDegrees: maxLeanR,
                            maxAccelG: maxAccel, maxBrakeG: maxBrake)
    }
}
