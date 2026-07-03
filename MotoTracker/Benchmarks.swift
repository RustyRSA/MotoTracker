import Foundation
import CoreLocation

enum BenchmarkKind: Equatable {
    case speedRange(from: Double, to: Double)   // m/s
    case standingDistance(meters: Double)       // from standstill
}

struct BenchmarkDefinition: Identifiable {
    let id: String
    let name: String
    let kind: BenchmarkKind

    static let mphSet: [BenchmarkDefinition] = [
        .init(id: "0-30mph",   name: "0–30 mph",    kind: .speedRange(from: 0, to: 30 / 2.23694)),
        .init(id: "0-60mph",   name: "0–60 mph",    kind: .speedRange(from: 0, to: 60 / 2.23694)),
        .init(id: "20-80mph",  name: "20–80 mph",   kind: .speedRange(from: 20 / 2.23694, to: 80 / 2.23694)),
        .init(id: "60-130mph", name: "60–130 mph",  kind: .speedRange(from: 60 / 2.23694, to: 130 / 2.23694)),
        .init(id: "1/8mile",   name: "1/8 mile",    kind: .standingDistance(meters: 201.168)),
        .init(id: "1/4mile",   name: "1/4 mile",    kind: .standingDistance(meters: 402.336)),
    ]

    static let kmhSet: [BenchmarkDefinition] = [
        .init(id: "0-100",   name: "0–100 km/h",   kind: .speedRange(from: 0, to: 100 / 3.6)),
        .init(id: "0-200",   name: "0–200 km/h",   kind: .speedRange(from: 0, to: 200 / 3.6)),
        .init(id: "60-120",  name: "60–120 km/h",  kind: .speedRange(from: 60 / 3.6, to: 120 / 3.6)),
        .init(id: "100-200", name: "100–200 km/h", kind: .speedRange(from: 100 / 3.6, to: 200 / 3.6)),
        .init(id: "400m",    name: "400 m",        kind: .standingDistance(meters: 400)),
    ]

    static func set(metric: Bool) -> [BenchmarkDefinition] { metric ? kmhSet : mphSet }
}

struct BenchmarkResult: Identifiable {
    var id: String { definition.id }
    let definition: BenchmarkDefinition
    let seconds: Double
    let endSpeed: Double    // m/s at completion (trap speed for distance runs)
}

enum BenchmarkEngine {

    /// Best (fastest) result for each definition found anywhere in the ride.
    static func results(for points: [RidePoint], definitions: [BenchmarkDefinition]) -> [BenchmarkResult] {
        definitions.compactMap { def in
            switch def.kind {
            case .speedRange(let from, let to):
                return bestSpeedRun(points: points, from: from, to: to, definition: def)
            case .standingDistance(let meters):
                return bestStandingDistance(points: points, meters: meters, definition: def)
            }
        }
    }

    private static func interpolatedTime(_ a: RidePoint, _ b: RidePoint, threshold: Double) -> Double {
        let ta = a.timestamp.timeIntervalSince1970
        let tb = b.timestamp.timeIntervalSince1970
        let dv = b.speed - a.speed
        guard dv > 0 else { return tb }
        let frac = min(max((threshold - a.speed) / dv, 0), 1)
        return ta + frac * (tb - ta)
    }

    private static func loc(_ p: RidePoint) -> CLLocation {
        CLLocation(latitude: p.latitude, longitude: p.longitude)
    }

    private static func bestSpeedRun(points: [RidePoint], from: Double, to: Double,
                                     definition: BenchmarkDefinition) -> BenchmarkResult? {
        guard points.count >= 2 else { return nil }
        let startsAtRest = from <= 0.1
        var best: BenchmarkResult?
        var i = 0
        while i < points.count - 1 {
            let a = points[i], b = points[i + 1]
            let crossesStart = startsAtRest
                ? (a.speed <= 0.5 && b.speed > 0.5)
                : (a.speed <= from && b.speed > from)
            if crossesStart {
                let t0 = startsAtRest
                    ? a.timestamp.timeIntervalSince1970
                    : interpolatedTime(a, b, threshold: from)
                let floor = startsAtRest ? 0.3 : from - 0.5
                var j = i + 1
                while j < points.count - 1 {
                    let p = points[j], q = points[j + 1]
                    if p.speed < floor { break }        // run aborted (slowed back down)
                    if p.speed <= to && q.speed > to {  // target speed reached
                        let t1 = interpolatedTime(p, q, threshold: to)
                        let dt = t1 - t0
                        if dt > 0.5, dt < 600, best == nil || dt < best!.seconds {
                            best = BenchmarkResult(definition: definition, seconds: dt, endSpeed: to)
                        }
                        break
                    }
                    j += 1
                }
                i = max(j, i + 1)
            } else {
                i += 1
            }
        }
        return best
    }

    private static func bestStandingDistance(points: [RidePoint], meters: Double,
                                             definition: BenchmarkDefinition) -> BenchmarkResult? {
        guard points.count >= 2 else { return nil }
        var best: BenchmarkResult?
        var i = 0
        while i < points.count - 1 {
            if points[i].speed <= 0.5 && points[i + 1].speed > 0.5 {
                let t0 = points[i].timestamp.timeIntervalSince1970
                var travelled = 0.0
                var j = i
                while j < points.count - 1 {
                    let p = points[j], q = points[j + 1]
                    if j > i + 1 && q.speed < 0.3 { break }   // came back to rest first
                    let seg = loc(p).distance(from: loc(q))
                    if travelled + seg >= meters {
                        let frac = seg > 0 ? (meters - travelled) / seg : 0
                        let tp = p.timestamp.timeIntervalSince1970
                        let tq = q.timestamp.timeIntervalSince1970
                        let t1 = tp + frac * (tq - tp)
                        let trap = p.speed + frac * (q.speed - p.speed)
                        let dt = t1 - t0
                        if dt > 3, dt < 600, best == nil || dt < best!.seconds {
                            best = BenchmarkResult(definition: definition, seconds: dt, endSpeed: trap)
                        }
                        break
                    }
                    travelled += seg
                    j += 1
                }
                i = max(j, i + 1)
            } else {
                i += 1
            }
        }
        return best
    }
}
