import Foundation

/// Generates realistic fake rides so every screen (History, Routes with a PB,
/// Records, speed graph, braking pins) has data without leaving the couch.
enum DemoRide {

    /// Adds two attempts of the same route at different pace:
    /// one 7 days ago (slower) and one 2 days ago (faster = the PB).
    static func addDemoRides(to store: RideStore) {
        let profile = buildProfile()
        let now = Date()
        store.add(makeRide(profile: profile, paceFactor: 0.92,
                           start: now.addingTimeInterval(-7 * 24 * 3600)))
        store.add(makeRide(profile: profile, paceFactor: 1.0,
                           start: now.addingTimeInterval(-2 * 24 * 3600)))
    }

    private struct Step {
        let speed: Double     // m/s
        let heading: Double   // degrees
    }

    /// 1 Hz speed/heading profile: launch with a ~4 s 0–100, sweepers, hard
    /// braking, tight corners (~35–40° lean), a stop, a second launch to
    /// ~160 km/h (covers the 400 m / quarter-mile), and a stop at the end.
    private static func buildProfile() -> [Step] {
        var steps: [Step] = []
        var speed = 0.0
        var heading = 40.0

        func hold(_ seconds: Int, accel: Double = 0, turnRate: Double = 0) {
            for _ in 0..<seconds {
                speed = max(0, speed + accel)
                heading += turnRate
                steps.append(Step(speed: speed, heading: heading))
            }
        }

        hold(5)                          // waiting at the start
        hold(4, accel: 7)                // launch: 0–100 km/h in ~4 s
        hold(3, accel: 3)                // on to ~133 km/h
        hold(20, turnRate: 2)            // fast sweepers
        hold(4, accel: -5)               // brake for the corner (braking pin)
        hold(4, turnRate: 23)            // right-hander, ~35° lean
        hold(4, turnRate: -20)           // left-hander
        hold(6, accel: 3)                // drive out
        hold(25, turnRate: -1.5)         // cruise
        hold(4, accel: -7)               // hard brake (big braking pin)
        hold(2, accel: -3.5)             // down to a stop
        hold(20)                         // traffic light
        hold(5, accel: 6)                // second launch
        hold(5, accel: 2.8)              // up to ~158 km/h (top speed)
        hold(10, turnRate: 1)            // hold it (finishes the 400 m run)
        hold(5, accel: -4)               // roll off
        hold(10, turnRate: 3)            // last corners
        hold(4, accel: -5)               // slow down
        hold(2, accel: -2)               // to a stop
        hold(4)                          // parked
        return steps
    }

    private static func makeRide(profile: [Step], paceFactor: Double, start: Date) -> Ride {
        var points: [RidePoint] = []
        var braking: [BrakingEvent] = []
        // Chapman's Peak Drive-ish, Western Cape
        var lat = -34.0550
        var lon = 18.3580
        var t = start
        var distance = 0.0
        var prevSpeed = 0.0
        var lastBrakeT: Date?
        let dt = 1.0 / paceFactor

        for (i, step) in profile.enumerated() {
            let speed = step.speed * paceFactor
            if i > 0 {
                // Geometry follows the base profile so both attempts share the
                // same path (speed' * dt' == baseSpeed * 1 s).
                let d = step.speed * 1.0
                let rad = step.heading * .pi / 180
                lat += d * cos(rad) / 111_111
                lon += d * sin(rad) / (111_111 * cos(lat * .pi / 180))
                distance += d
                t = t.addingTimeInterval(dt)

                let decel = (prevSpeed - speed) / dt
                let cooldownOK = lastBrakeT.map { t.timeIntervalSince($0) > 3 } ?? true
                if decel >= 3, prevSpeed > 3, cooldownOK {
                    braking.append(BrakingEvent(
                        latitude: lat, longitude: lon,
                        deceleration: decel,
                        fromSpeed: prevSpeed, toSpeed: speed,
                        timestamp: t))
                    lastBrakeT = t
                }
            }
            var course = step.heading.truncatingRemainder(dividingBy: 360)
            if course < 0 { course += 360 }
            points.append(RidePoint(latitude: lat, longitude: lon,
                                    speed: speed, course: course, timestamp: t))
            prevSpeed = speed
        }

        return Ride(id: UUID(), startDate: start, endDate: t,
                    points: points, brakingEvents: braking,
                    distanceMeters: distance)
    }
}
