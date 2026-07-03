import Foundation

struct RidePoint: Codable {
    let latitude: Double
    let longitude: Double
    let speed: Double        // m/s, always >= 0
    let course: Double       // degrees 0-360, -1 if invalid
    let altitude: Double?    // meters; nil on invalid fix or rides recorded before v1.2
    let timestamp: Date
}

struct BrakingEvent: Codable, Identifiable {
    var id = UUID()
    let latitude: Double
    let longitude: Double
    let deceleration: Double // m/s^2, positive value
    let fromSpeed: Double    // m/s
    let toSpeed: Double      // m/s
    let timestamp: Date
}

struct Ride: Codable, Identifiable {
    let id: UUID
    let startDate: Date
    let endDate: Date
    let points: [RidePoint]
    let brakingEvents: [BrakingEvent]
    let distanceMeters: Double

    var duration: TimeInterval { endDate.timeIntervalSince(startDate) }

    var maxSpeed: Double { points.map(\.speed).max() ?? 0 }

    /// Average speed while moving (> 1 m/s), so stops at lights don't drag it down.
    var avgMovingSpeed: Double {
        let moving = points.filter { $0.speed > 1 }
        guard !moving.isEmpty else { return 0 }
        return moving.map(\.speed).reduce(0, +) / Double(moving.count)
    }
}
