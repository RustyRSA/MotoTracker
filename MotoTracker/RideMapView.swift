import SwiftUI
import MapKit

/// A pin on the ride map. Kind controls color, glyph and display priority.
struct RideMapMarker {
    enum Kind {
        case braking        // orange, warning triangle
        case hardAccel      // green, bolt
        case record         // purple, rosette — best of this ride
        case allTimeRecord  // yellow, star — best across all rides
    }
    let kind: Kind
    let latitude: Double
    let longitude: Double
    let title: String
    let subtitle: String
}

final class RideMarkerAnnotation: MKPointAnnotation {
    var kind: RideMapMarker.Kind = .braking
}

struct RideMapView: UIViewRepresentable {
    let points: [RidePoint]
    var markers: [RideMapMarker] = []
    var followsUser: Bool = false
    var highlight: CLLocationCoordinate2D? = nil
    /// While true, the camera tracks `highlight` (zoomed in); when it flips
    /// back to false the map animates back out to the whole route.
    var followHighlight: Bool = false

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = followsUser
        if followsUser {
            map.userTrackingMode = .follow
        }
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let coordinator = context.coordinator

        if coordinator.renderedPointCount != points.count
            || coordinator.renderedMarkerCount != markers.count {
            coordinator.renderedPointCount = points.count
            coordinator.renderedMarkerCount = markers.count
            map.removeOverlays(map.overlays)
            let old = map.annotations.filter { !($0 is MKUserLocation) && $0 !== coordinator.highlightPin }
            map.removeAnnotations(old)

            if points.count >= 2 {
                coordinator.speeds = points.map(\.speed)
                coordinator.maxSpeed = max(points.map(\.speed).max() ?? 1, 1)

                let coords = points.map {
                    CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                }
                let polyline = MKPolyline(coordinates: coords, count: coords.count)
                map.addOverlay(polyline)

                if !followsUser {
                    map.setVisibleMapRect(
                        polyline.boundingMapRect,
                        edgePadding: UIEdgeInsets(top: 40, left: 40, bottom: 40, right: 40),
                        animated: false
                    )
                }
            }

            for marker in markers {
                let pin = RideMarkerAnnotation()
                pin.kind = marker.kind
                pin.coordinate = CLLocationCoordinate2D(latitude: marker.latitude,
                                                        longitude: marker.longitude)
                pin.title = marker.title
                pin.subtitle = marker.subtitle
                map.addAnnotation(pin)
            }
        }

        if let hl = highlight {
            if coordinator.highlightPin == nil {
                let pin = MKPointAnnotation()
                pin.title = "Scrub"
                coordinator.highlightPin = pin
                map.addAnnotation(pin)
            }
            coordinator.highlightPin?.coordinate = hl

            if followHighlight {
                if coordinator.isFollowingHighlight {
                    map.setCenter(hl, animated: false)   // instant, keeps up with the finger
                } else {
                    // First scrub tick: zoom from the overview onto the spot.
                    coordinator.isFollowingHighlight = true
                    map.setRegion(MKCoordinateRegion(center: hl,
                                                     latitudinalMeters: 700,
                                                     longitudinalMeters: 700),
                                  animated: true)
                }
            } else if coordinator.isFollowingHighlight {
                // Finger lifted: zoom back out, dot stays where it was.
                coordinator.isFollowingHighlight = false
                Self.fitWholeRoute(map, animated: true)
            }
        } else if let pin = coordinator.highlightPin {
            map.removeAnnotation(pin)
            coordinator.highlightPin = nil
            if coordinator.isFollowingHighlight {
                coordinator.isFollowingHighlight = false
                Self.fitWholeRoute(map, animated: true)
            }
        }
    }

    private static func fitWholeRoute(_ map: MKMapView, animated: Bool) {
        guard let polyline = map.overlays.first(where: { $0 is MKPolyline }) else { return }
        map.setVisibleMapRect(
            polyline.boundingMapRect,
            edgePadding: UIEdgeInsets(top: 40, left: 40, bottom: 40, right: 40),
            animated: animated
        )
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var speeds: [Double] = []
        var maxSpeed: Double = 1
        var renderedPointCount = -1
        var renderedMarkerCount = -1
        var highlightPin: MKPointAnnotation?
        var isFollowingHighlight = false
        var didSetInitialUserRegion = false

        /// Live map only (showsUserLocation is set just for followsUser maps):
        /// first valid fix zooms to the user at neighborhood level, once.
        func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
            guard !didSetInitialUserRegion else { return }
            let c = userLocation.coordinate
            guard CLLocationCoordinate2DIsValid(c),
                  abs(c.latitude) > 0.000001 || abs(c.longitude) > 0.000001 else { return }
            didSetInitialUserRegion = true
            mapView.setRegion(MKCoordinateRegion(center: c,
                                                 latitudinalMeters: 1200,
                                                 longitudinalMeters: 1200),
                              animated: true)
            // Programmatic region changes can knock tracking off — re-assert.
            if mapView.userTrackingMode != .follow {
                mapView.userTrackingMode = .follow
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let renderer = MKGradientPolylineRenderer(polyline: polyline)
            // Fixed width in screen points. Road-scaled (lineWidth = 0) balloons
            // far wider than the road once you zoom out over a whole ride.
            renderer.lineWidth = 5
            renderer.lineCap = .round

            if speeds.count >= 2 {
                let smooth = Self.smoothed(speeds)
                let n = smooth.count
                var colors: [UIColor] = []
                var fractions: [CGFloat] = []
                for (i, speed) in smooth.enumerated() {
                    colors.append(Self.color(for: speed, maxSpeed: maxSpeed))
                    fractions.append(CGFloat(i) / CGFloat(n - 1))
                }
                renderer.setColors(colors, locations: fractions)
            } else {
                renderer.strokeColor = .systemGreen
            }
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard !(annotation is MKUserLocation) else { return nil }

            // Scrub dot: a plain annotation view (not a marker), so it never
            // takes part in marker collision and can't be hidden by other pins.
            if (annotation as? MKPointAnnotation) === highlightPin {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: "scrub")
                    ?? MKAnnotationView(annotation: annotation, reuseIdentifier: "scrub")
                view.annotation = annotation
                view.image = Self.scrubDot
                view.displayPriority = .required
                view.zPriority = .max
                view.canShowCallout = false
                return view
            }

            guard let marker = annotation as? RideMarkerAnnotation else { return nil }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: "marker") as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "marker")
            view.annotation = annotation
            view.canShowCallout = true   // tap for title + exact numbers
            switch marker.kind {
            case .braking:
                view.markerTintColor = .systemOrange
                view.glyphImage = UIImage(systemName: "exclamationmark.triangle.fill")
                view.displayPriority = .defaultHigh
            case .hardAccel:
                view.markerTintColor = .systemGreen
                view.glyphImage = UIImage(systemName: "bolt.fill")
                view.displayPriority = .defaultHigh
            case .record:
                view.markerTintColor = .systemPurple
                view.glyphImage = UIImage(systemName: "rosette")
                view.displayPriority = .required
            case .allTimeRecord:
                view.markerTintColor = .systemYellow
                view.glyphImage = UIImage(systemName: "star.fill")
                view.displayPriority = .required
            }
            return view
        }

        /// Blue dot with a white ring, drawn once — sits on the route line.
        static let scrubDot: UIImage = {
            let size = CGSize(width: 18, height: 18)
            return UIGraphicsImageRenderer(size: size).image { _ in
                let path = UIBezierPath(ovalIn: CGRect(x: 1.5, y: 1.5, width: 15, height: 15))
                UIColor.systemBlue.setFill()
                path.fill()
                UIColor.white.setStroke()
                path.lineWidth = 3
                path.stroke()
            }
        }()

        /// 3-point moving average so the gradient shifts smoothly instead
        /// of flickering with every GPS fix.
        static func smoothed(_ values: [Double]) -> [Double] {
            guard values.count > 2 else { return values }
            var out = values
            for i in 1..<(values.count - 1) {
                out[i] = (values[i - 1] + values[i] + values[i + 1]) / 3
            }
            return out
        }

        /// Green (slow) -> yellow -> red (fast)
        static func color(for speed: Double, maxSpeed: Double) -> UIColor {
            let t = CGFloat(min(max(speed / maxSpeed, 0), 1))
            return UIColor(hue: (1 - t) * 0.33, saturation: 0.9, brightness: 0.9, alpha: 1)
        }
    }
}
