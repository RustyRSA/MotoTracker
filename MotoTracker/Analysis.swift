import Foundation
import CoreLocation

/// One chart point of any per-ride series. `id` is the index into
/// `ride.points`, which is what links chart scrubbing to the map.
struct MetricSample: Identifiable {
    let id: Int
    let t: Double        // seconds since ride start
    let value: Double    // unit depends on the series
}

struct RideAnalysis {
    let maxLeanLeftDegrees: Double
    let maxLeanRightDegrees: Double
    let maxAccelG: Double
    let maxBrakeG: Double

    /// Larger of the two sides, for places that want a single figure.
    var maxLeanDegrees: Double { max(maxLeanLeftDegrees, maxLeanRightDegrees) }
}

struct ExtremePoint {
    let index: Int       // index into ride.points where it happened
    let value: Double
}

/// Where in the ride each maximum happened, for map markers.
struct RideExtremes {
    var topSpeed: ExtremePoint?      // m/s
    var maxAccelG: ExtremePoint?     // g
    var maxBrakeG: ExtremePoint?     // g
    var maxLean: ExtremePoint?       // degrees, bigger of the two sides
    var maxLeanIsRight = false
}

/// Hard acceleration derived from stored points at view time (unlike braking,
/// which is detected live and persisted), so it works on already-saved rides.
struct HardAccelEvent {
    let index: Int       // point index at the end of the interval
    let accel: Double    // m/s^2
    let fromSpeed: Double
    let toSpeed: Double
}

enum RideMath {

    // MARK: - Chart series (all index-aligned to ride.points via `id`)

    static func speedSamples(_ points: [RidePoint]) -> [MetricSample] {
        guard let start = points.first?.timestamp else { return [] }
        return points.enumerated().map { i, p in
            MetricSample(id: i, t: p.timestamp.timeIntervalSince(start), value: p.speed)
        }
    }

    /// Longitudinal acceleration in g, spike-filtered and lightly smoothed.
    static func accelSamples(_ points: [RidePoint]) -> [MetricSample] {
        guard let start = points.first?.timestamp, points.count >= 2 else { return [] }
        var g = [Double](repeating: 0, count: points.count)
        for i in 1..<points.count {
            let a = points[i - 1], b = points[i]
            let dt = b.timestamp.timeIntervalSince(a.timestamp)
            guard dt > 0.2 else { continue }
            let v = (b.speed - a.speed) / dt / 9.81
            if abs(v) < 1.6 { g[i] = v }
        }
        let smooth = smoothed3(g)
        return points.enumerated().map { i, p in
            MetricSample(id: i, t: p.timestamp.timeIntervalSince(start), value: smooth[i])
        }
    }

    /// Lean angle in degrees, signed: negative = left, positive = right.
    static func leanSamples(_ points: [RidePoint]) -> [MetricSample] {
        guard let start = points.first?.timestamp, points.count >= 2 else { return [] }
        var lean = [Double](repeating: 0, count: points.count)
        for i in 1..<points.count {
            let a = points[i - 1], b = points[i]
            let dt = b.timestamp.timeIntervalSince(a.timestamp)
            guard dt > 0.2, a.course >= 0, b.course >= 0, b.speed > 3 else { continue }
            var d = b.course - a.course
            if d > 180 { d -= 360 }
            if d < -180 { d += 360 }
            let omega = abs(d) * .pi / 180 / dt
            let angle = atan(b.speed * omega / 9.81) * 180 / .pi
            if angle < 65 { lean[i] = d < 0 ? -angle : angle }
        }
        let smooth = smoothed3(lean)
        return points.enumerated().map { i, p in
            MetricSample(id: i, t: p.timestamp.timeIntervalSince(start), value: smooth[i])
        }
    }

    /// Only points that carry an altitude (rides recorded before v1.2 have none).
    static func elevationSamples(_ points: [RidePoint]) -> [MetricSample] {
        guard let start = points.first?.timestamp else { return [] }
        var out: [MetricSample] = []
        for (i, p) in points.enumerated() {
            if let alt = p.altitude {
                out.append(MetricSample(id: i, t: p.timestamp.timeIntervalSince(start), value: alt))
            }
        }
        return out
    }

    // MARK: - Ride maxima

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

    /// Same filters as `analysis`, but also records *where* each maximum happened.
    static func extremes(_ points: [RidePoint]) -> RideExtremes {
        var ex = RideExtremes()
        guard points.count >= 2 else { return ex }

        var bestSpeed = 0.0, bestSpeedIdx = -1
        for (i, p) in points.enumerated() where p.speed > bestSpeed {
            bestSpeed = p.speed
            bestSpeedIdx = i
        }
        if bestSpeedIdx >= 0, bestSpeed > 1 {
            ex.topSpeed = ExtremePoint(index: bestSpeedIdx, value: bestSpeed)
        }

        for i in 0..<(points.count - 1) {
            let a = points[i], b = points[i + 1]
            let dt = b.timestamp.timeIntervalSince(a.timestamp)
            guard dt > 0.2 else { continue }

            let g = (b.speed - a.speed) / dt / 9.81
            if abs(g) < 1.6 {
                if g > 0, g > (ex.maxAccelG?.value ?? 0) {
                    ex.maxAccelG = ExtremePoint(index: i + 1, value: g)
                } else if g < 0, -g > (ex.maxBrakeG?.value ?? 0) {
                    ex.maxBrakeG = ExtremePoint(index: i + 1, value: -g)
                }
            }

            if a.course >= 0, b.course >= 0, b.speed > 3 {
                var d = b.course - a.course
                if d > 180 { d -= 360 }
                if d < -180 { d += 360 }
                let omega = abs(d) * .pi / 180 / dt
                let lean = atan(b.speed * omega / 9.81) * 180 / .pi
                if lean < 65, d != 0, lean > (ex.maxLean?.value ?? 0) {
                    ex.maxLean = ExtremePoint(index: i + 1, value: lean)
                    ex.maxLeanIsRight = d > 0
                }
            }
        }
        return ex
    }

    /// Hard acceleration events (mirror of live braking detection: threshold,
    /// spike sanity cap, 3 s cooldown).
    static func hardAccelEvents(_ points: [RidePoint],
                                threshold: Double = 4.0) -> [HardAccelEvent] {
        guard points.count >= 2 else { return [] }
        var out: [HardAccelEvent] = []
        var lastTime: Date?
        for i in 0..<(points.count - 1) {
            let a = points[i], b = points[i + 1]
            let dt = b.timestamp.timeIntervalSince(a.timestamp)
            guard dt > 0.2, dt < 3 else { continue }
            let accel = (b.speed - a.speed) / dt
            guard accel >= threshold, accel < 15 else { continue }   // >1.5 g is a GPS glitch
            let cooldownOK = lastTime.map { b.timestamp.timeIntervalSince($0) > 3 } ?? true
            guard cooldownOK else { continue }
            out.append(HardAccelEvent(index: i + 1, accel: accel,
                                      fromSpeed: a.speed, toSpeed: b.speed))
            lastTime = b.timestamp
        }
        return out
    }

    /// 3-point moving average — takes the flicker out of 1 Hz derivatives.
    private static func smoothed3(_ values: [Double]) -> [Double] {
        guard values.count > 2 else { return values }
        var out = values
        for i in 1..<(values.count - 1) {
            out[i] = (values[i - 1] + values[i] + values[i + 1]) / 3
        }
        return out
    }
}
