import Foundation
import CoreLocation

struct RouteGroup: Identifiable {
    let id: UUID          // id of the first (reference) ride
    let name: String
    let rides: [Ride]     // chronological

    var referenceRide: Ride { rides[0] }
    var attemptCount: Int { rides.count }
    var bestRide: Ride? { rides.min { $0.duration < $1.duration } }
    var bestTopSpeed: Double { rides.map(\.maxSpeed).max() ?? 0 }
    var distanceMeters: Double { referenceRide.distanceMeters }
}

enum RouteMatcher {

    /// Groups rides that follow the same road in the same direction.
    static func groups(from rides: [Ride]) -> [RouteGroup] {
        var buckets: [[Ride]] = []
        for ride in rides.sorted(by: { $0.startDate < $1.startDate }) {
            guard ride.points.count >= 10, ride.distanceMeters > 300 else { continue }
            if let idx = buckets.firstIndex(where: { matches($0[0], ride) }) {
                buckets[idx].append(ride)
            } else {
                buckets.append([ride])
            }
        }
        return buckets.enumerated().map { i, rides in
            RouteGroup(id: rides[0].id, name: "Route \(i + 1)", rides: rides)
        }
    }

    static func matches(_ a: Ride, _ b: Ride) -> Bool {
        guard let aFirst = a.points.first, let aLast = a.points.last,
              let bFirst = b.points.first, let bLast = b.points.last else { return false }

        let ratio = a.distanceMeters / max(b.distanceMeters, 1)
        guard ratio > 0.8, ratio < 1.25 else { return false }

        guard loc(aFirst).distance(from: loc(bFirst)) < 250,
              loc(aLast).distance(from: loc(bLast)) < 250 else { return false }

        let ra = resample(a.points, count: 32)
        let rb = resample(b.points, count: 32)
        guard ra.count == rb.count, !ra.isEmpty else { return false }
        let meanDeviation = zip(ra, rb).map { $0.distance(from: $1) }.reduce(0, +) / Double(ra.count)
        return meanDeviation < 120
    }

    private static func loc(_ p: RidePoint) -> CLLocation {
        CLLocation(latitude: p.latitude, longitude: p.longitude)
    }

    /// Resamples a path to `count` points evenly spaced by travelled distance.
    private static func resample(_ points: [RidePoint], count: Int) -> [CLLocation] {
        guard points.count >= 2, count >= 2 else { return [] }
        var cumulative: [Double] = [0]
        for i in 1..<points.count {
            cumulative.append(cumulative[i - 1] + loc(points[i - 1]).distance(from: loc(points[i])))
        }
        let total = cumulative.last ?? 0
        guard total > 0 else { return [] }

        var result: [CLLocation] = []
        var seg = 0
        for k in 0..<count {
            let target = total * Double(k) / Double(count - 1)
            while seg < points.count - 2 && cumulative[seg + 1] < target { seg += 1 }
            let segLen = cumulative[seg + 1] - cumulative[seg]
            let frac = segLen > 0 ? (target - cumulative[seg]) / segLen : 0
            let p = points[seg], q = points[seg + 1]
            result.append(CLLocation(
                latitude: p.latitude + frac * (q.latitude - p.latitude),
                longitude: p.longitude + frac * (q.longitude - p.longitude)
            ))
        }
        return result
    }
}
