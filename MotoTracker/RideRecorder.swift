import Foundation
import CoreLocation

final class RideRecorder: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var isRecording = false
    @Published var autoArmed = false                 // significant-change monitoring active
    @Published var currentSpeed: Double = 0          // m/s
    @Published var topSpeed: Double = 0              // m/s, this ride
    @Published var currentG: Double = 0              // longitudinal, +accel / -brake
    @Published var currentLean: Double = 0           // degrees
    @Published var points: [RidePoint] = []
    @Published var brakingEvents: [BrakingEvent] = []
    @Published var distance: Double = 0              // meters
    @Published var startDate: Date?
    @Published var authorizationDenied = false

    /// Set once at app launch so auto-detected rides can save themselves.
    weak var store: RideStore?

    private let manager = CLLocationManager()
    private var lastLocation: CLLocation?
    private var lastBrakingTime: Date?
    private var lastMovementTime: Date?
    private var startedAutomatically = false

    // Auto-detection state
    private enum AutoState { case idle, probing }
    private var autoState: AutoState = .idle
    private var probeStart: Date?
    private var movingFixCount = 0
    private var probeBuffer: [CLLocation] = []

    // MARK: - Tunables

    /// Deceleration (m/s^2) that counts as hard braking. ~3 m/s^2 is firm braking on a bike.
    let brakingThreshold: Double = 3.0
    /// Sustained speed (m/s, ~18 km/h) that auto-starts a ride.
    let autoStartSpeed: Double = 5.0
    /// Number of fixes at/above autoStartSpeed needed to auto-start.
    let autoStartFixes = 3
    /// GPS probe gives up after this many seconds without sustained movement.
    let probeTimeout: TimeInterval = 90
    /// Stationary seconds before an auto-started ride saves itself.
    let autoStopAfter: TimeInterval = 180

    private var autoEnabled: Bool { UserDefaults.standard.bool(forKey: "autoRecord") }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .automotiveNavigation
        manager.distanceFilter = kCLDistanceFilterNone   // every fix, ~1 Hz
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    // MARK: - Auto-record mode

    /// Called at app launch (including when iOS relaunches the app for a location event).
    func resumeAutoModeIfEnabled() {
        if autoEnabled { setAutoMode(true) }
    }

    func setAutoMode(_ on: Bool) {
        if on {
            manager.requestAlwaysAuthorization()
            manager.startMonitoringSignificantLocationChanges()
            autoArmed = true
        } else {
            manager.stopMonitoringSignificantLocationChanges()
            if autoState == .probing { endProbe() }
            autoArmed = false
        }
    }

    private func handleAutoDetection(_ location: CLLocation) {
        if autoState == .idle {
            // Woken by a significant location change: probe with full GPS.
            autoState = .probing
            probeStart = Date()
            movingFixCount = 0
            probeBuffer = []
            manager.startUpdatingLocation()
        }
        evaluateProbe(location)
    }

    private func evaluateProbe(_ location: CLLocation) {
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 50 else { return }
        probeBuffer.append(location)
        if probeBuffer.count > 120 { probeBuffer.removeFirst() }

        if max(0, location.speed) >= autoStartSpeed {
            movingFixCount += 1
        }
        if movingFixCount >= autoStartFixes {
            beginAutoRide()
            return
        }
        if let s = probeStart, Date().timeIntervalSince(s) > probeTimeout {
            endProbe()
        }
    }

    private func endProbe() {
        autoState = .idle
        probeStart = nil
        probeBuffer = []
        manager.stopUpdatingLocation()   // significant-change monitoring stays armed
    }

    private func beginAutoRide() {
        autoState = .idle
        probeStart = nil
        startedAutomatically = true
        resetRideState()
        startDate = probeBuffer.first?.timestamp ?? Date()
        lastMovementTime = Date()
        isRecording = true
        configureForContinuousUpdates()
        let buffered = probeBuffer
        probeBuffer = []
        for loc in buffered { process(loc) }   // don't lose the first few hundred meters
    }

    // MARK: - Manual control

    func start() {
        startedAutomatically = false
        resetRideState()
        startDate = Date()
        lastMovementTime = Date()
        isRecording = true
        manager.requestWhenInUseAuthorization()
        configureForContinuousUpdates()
        manager.startUpdatingLocation()
    }

    func stopRide() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        isRecording = false

        if startedAutomatically {
            // Drop the trailing stationary minutes before the auto-stop fired.
            while let last = points.last, last.speed < 0.5, points.count > 2 {
                points.removeLast()
            }
        }
        let end = startedAutomatically ? (points.last?.timestamp ?? Date()) : Date()

        defer {
            startedAutomatically = false
            autoState = .idle
        }
        guard let start = startDate, points.count >= 2 else { return }
        let ride = Ride(
            id: UUID(),
            startDate: start,
            endDate: end,
            points: points,
            brakingEvents: brakingEvents,
            distanceMeters: distance
        )
        store?.add(ride)
    }

    private func resetRideState() {
        points = []
        brakingEvents = []
        distance = 0
        currentSpeed = 0
        topSpeed = 0
        currentG = 0
        currentLean = 0
        lastLocation = nil
        lastBrakingTime = nil
    }

    private func configureForContinuousUpdates() {
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        authorizationDenied = (status == .denied || status == .restricted)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for location in locations {
            if isRecording {
                process(location)
            } else if autoEnabled {
                handleAutoDetection(location)
            }
        }
    }

    private func process(_ location: CLLocation) {
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 35 else { return }
        let speed = max(0, location.speed)
        currentSpeed = speed
        topSpeed = max(topSpeed, speed)

        // Auto-stop: stationary for a while ends an auto-started ride.
        if startedAutomatically {
            if speed >= 1 {
                lastMovementTime = location.timestamp
            } else if let lm = lastMovementTime,
                      location.timestamp.timeIntervalSince(lm) > autoStopAfter {
                appendPoint(location, speed: speed)
                stopRide()
                return
            }
        }

        if let last = lastLocation {
            let dt = location.timestamp.timeIntervalSince(last.timestamp)
            if dt > 0.2 {
                let lastSpeed = max(0, last.speed)
                let accel = (speed - lastSpeed) / dt

                // Live longitudinal G (filter GPS spikes)
                let g = accel / 9.81
                if abs(g) < 1.6 { currentG = g }

                // Live lean from turn rate
                if last.course >= 0, location.course >= 0, speed > 3 {
                    var d = location.course - last.course
                    if d > 180 { d -= 360 }
                    if d < -180 { d += 360 }
                    let omega = abs(d) * .pi / 180 / dt
                    let lean = atan(speed * omega / 9.81) * 180 / .pi
                    if lean < 65 { currentLean = lean }
                } else {
                    currentLean = 0
                }

                // Hard braking event
                let decel = -accel
                let cooldownOK = lastBrakingTime.map { location.timestamp.timeIntervalSince($0) > 3 } ?? true
                if decel >= brakingThreshold, lastSpeed > 3, cooldownOK {
                    brakingEvents.append(BrakingEvent(
                        latitude: location.coordinate.latitude,
                        longitude: location.coordinate.longitude,
                        deceleration: decel,
                        fromSpeed: lastSpeed,
                        toSpeed: speed,
                        timestamp: location.timestamp
                    ))
                    lastBrakingTime = location.timestamp
                }
            }
            distance += location.distance(from: last)
        }

        appendPoint(location, speed: speed)
    }

    private func appendPoint(_ location: CLLocation, speed: Double) {
        points.append(RidePoint(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            speed: speed,
            course: location.course,
            timestamp: location.timestamp
        ))
        lastLocation = location
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Transient GPS errors are expected; keep recording.
    }
}
