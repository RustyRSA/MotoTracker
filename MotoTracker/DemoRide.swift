import Foundation
import CoreLocation
import MapKit

/// Generates realistic fake rides so every screen (History, Routes with a PB,
/// Records, speed graph, braking pins) has data without leaving the couch.
/// The path comes from Apple Maps driving directions, so it follows real roads.
enum DemoRide {

    /// Adds two attempts of the same route at different pace:
    /// one 7 days ago (slower) and one 2 days ago (faster = the PB).
    /// Routes near your last recorded ride if one exists, else Cape Town.
    static func addDemoRides(to store: RideStore) {
        let origin: CLLocationCoordinate2D
        if let p = store.rides.first?.points.first {
            origin = CLLocationCoordinate2D(latitude: p.latitude, longitude: p.longitude)
        } else {
            origin = CLLocationCoordinate2D(latitude: -33.9249, longitude: 18.4241) // Cape Town
        }
        let destination = CLLocationCoordinate2D(latitude: origin.latitude + 0.05,
                                                 longitude: origin.longitude + 0.03)

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = .automobile

        MKDirections(request: request).calculate { response, _ in
            DispatchQueue.main.async {
                let path: [CLLocationCoordinate2D]
                if let polyline = response?.routes.first?.polyline {
                    var coords = [CLLocationCoordinate2D](
                        repeating: kCLLocationCoordinate2DInvalid,
                        count: polyline.pointCount)
                    polyline.getCoordinates(&coords, range: NSRange(location: 0, length: polyline.pointCount))
                    path = coords
                } else {
                    path = []   // offline / routing failed: fall back below
                }
                add(along: path, origin: origin, to: store)
            }
        }
    }

    private static func add(along path: [CLLocationCoordinate2D],
                            origin: CLLocationCoordinate2D,
                            to store: RideStore) {
        let profile = speedProfile()
        let now = Date()
        let usablePath = path.count >= 2 ? path : straightFallback(from: origin)

        if let slow = makeRide(along: usablePath, profile: profile, paceFactor: 0.92,
                               start: now.addingTimeInterval(-7 * 24 * 3600)) {
            store.add(slow)
        }
        if let fast = makeRide(along: usablePath, profile: profile, paceFactor: 1.0,
                               start: now.addingTimeInterval(-2 * 24 * 3600)) {
            store.add(fast)
        }
    }

    /// 1 Hz speeds (m/s): launch with a ~4 s 0–100, sweepers, hard braking,
    /// a stop, a second launch to ~160 km/h (covers the 400 m run), stop at end.
    private static func speedProfile() -> [Double] {
        var speeds: [Double] = []
        var v = 0.0
        func hold(_ seconds: Int, accel: Double = 0) {
            for _ in 0..<seconds {
                v = max(0, v + accel)
                speeds.append(v)
            }
        }
        hold(5)                 // waiting at the start
        hold(4, accel: 7)       // launch: 0–100 km/h in ~4 s
        hold(3, accel: 3)       // on to ~133 km/h
        hold(20)                // fast stretch
        hold(4, accel: -5)      // brake for corners (braking pin)
        hold(8)                 // through the corners
        hold(6, accel: 3)       // drive out
        hold(25)                // cruise
        hold(4, accel: -7)      // hard brake (big braking pin)
        hold(2, accel: -3.5)    // down to a stop
        hold(20)                // traffic light
        hold(5, accel: 6)       // second launch
        hold(5, accel: 2.8)     // up to ~158 km/h (top speed)
        hold(10)                // hold it (finishes the 400 m run)
        hold(5, accel: -4)      // roll off
        hold(10)                // last stretch
        hold(4, accel: -5)      // slow down
        hold(2, accel: -2)      // to a stop
        hold(4)                 // parked
        return speeds
    }

    /// Walks the speed profile along a real road polyline.
    /// Geometry uses base speeds so both attempts share the exact same path.
    private static func makeRide(along coords: [CLLocationCoordinate2D],
                                 profile: [Double],
                                 paceFactor: Double,
                                 start: Date) -> Ride? {
        guard coords.count >= 2 else { return nil }

        var cum: [Double] = [0]
        for i in 1..<coords.count {
            let a = CLLocation(latitude: coords[i-1].latitude, longitude: coords[i-1].longitude)
            let b = CLLocation(latitude: coords[i].latitude, longitude: coords[i].longitude)
            cum.append(cum[i-1] + a.distance(from: b))
        }
        let total = cum[cum.count - 1]

        var seg = 0
        func position(at target: Double) -> CLLocationCoordinate2D {
            while seg < coords.count - 2 && cum[seg + 1] < target { seg += 1 }
            let len = cum[seg + 1] - cum[seg]
            let f = len > 0 ? (target - cum[seg]) / len : 0
            return CLLocationCoordinate2D(
                latitude: coords[seg].latitude + f * (coords[seg + 1].latitude - coords[seg].latitude),
                longitude: coords[seg].longitude + f * (coords[seg + 1].longitude - coords[seg].longitude))
        }

        var points: [RidePoint] = []
        var braking: [BrakingEvent] = []
        var t = start
        var travelled = 0.0
        var prevSpeed = 0.0
        var prevCoord = coords[0]
        var lastCourse = -1.0
        var lastBrakeT: Date?
        let dt = 1.0 / paceFactor

        for (i, baseSpeed) in profile.enumerated() {
            let speed = baseSpeed * paceFactor
            if i > 0 {
                travelled += baseSpeed
                if travelled > total { break }
                t = t.addingTimeInterval(dt)
            }
            let coord = position(at: min(travelled, total))
            let course = bearing(from: prevCoord, to: coord)
            if course >= 0 { lastCourse = course }

            if i > 0 {
                let decel = (prevSpeed - speed) / dt
                let cooldownOK = lastBrakeT.map { t.timeIntervalSince($0) > 3 } ?? true
                if decel >= 3, prevSpeed > 3, cooldownOK {
                    braking.append(BrakingEvent(
                        latitude: coord.latitude, longitude: coord.longitude,
                        deceleration: decel,
                        fromSpeed: prevSpeed, toSpeed: speed,
                        timestamp: t))
                    lastBrakeT = t
                }
            }

            points.append(RidePoint(latitude: coord.latitude, longitude: coord.longitude,
                                    speed: speed, course: lastCourse, timestamp: t))
            prevSpeed = speed
            prevCoord = coord
        }

        guard points.count >= 10 else { return nil }
        return Ride(id: UUID(), startDate: start, endDate: t,
                    points: points, brakingEvents: braking,
                    distanceMeters: min(travelled, total))
    }

    private static func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let dLat = b.latitude - a.latitude
        let dLon = b.longitude - a.longitude
        if abs(dLat) < 1e-9, abs(dLon) < 1e-9 { return -1 }   // no movement
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dl = dLon * .pi / 180
        let y = sin(dl) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dl)
        var deg = atan2(y, x) * 180 / .pi
        if deg < 0 { deg += 360 }
        return deg
    }

    /// Last-resort path if routing is unavailable (offline): a straight line,
    /// clearly marked by nothing lining up — but the button still works.
    private static func straightFallback(from origin: CLLocationCoordinate2D) -> [CLLocationCoordinate2D] {
        (0...100).map { i in
            CLLocationCoordinate2D(latitude: origin.latitude + Double(i) * 0.0005,
                                   longitude: origin.longitude + Double(i) * 0.0003)
        }
    }
}
