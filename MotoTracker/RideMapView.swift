import SwiftUI
import MapKit

struct RideMapView: UIViewRepresentable {
    let points: [RidePoint]
    let brakingEvents: [BrakingEvent]
    var followsUser: Bool = false
    var highlight: CLLocationCoordinate2D? = nil

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

        if coordinator.renderedPointCount != points.count {
            coordinator.renderedPointCount = points.count
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

                for event in brakingEvents {
                    let pin = MKPointAnnotation()
                    pin.coordinate = CLLocationCoordinate2D(latitude: event.latitude, longitude: event.longitude)
                    pin.title = "Hard braking"
                    pin.subtitle = String(format: "%.1f m/s²", event.deceleration)
                    map.addAnnotation(pin)
                }

                if !followsUser {
                    map.setVisibleMapRect(
                        polyline.boundingMapRect,
                        edgePadding: UIEdgeInsets(top: 40, left: 40, bottom: 40, right: 40),
                        animated: false
                    )
                }
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
        } else if let pin = coordinator.highlightPin {
            map.removeAnnotation(pin)
            coordinator.highlightPin = nil
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var speeds: [Double] = []
        var maxSpeed: Double = 1
        var renderedPointCount = -1
        var highlightPin: MKPointAnnotation?

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let renderer = MKGradientPolylineRenderer(polyline: polyline)
            // lineWidth 0 = scale with the map like a road, so it stays
            // slim when zoomed out and readable when zoomed in.
            renderer.lineWidth = 0
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
            let isScrub = (annotation as? MKPointAnnotation) === highlightPin
            let identifier = isScrub ? "scrub" : "brake"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            view.annotation = annotation
            if isScrub {
                view.markerTintColor = .systemBlue
                view.glyphImage = UIImage(systemName: "location.fill")
            } else {
                view.markerTintColor = .systemOrange
                view.glyphImage = UIImage(systemName: "exclamationmark.triangle.fill")
            }
            return view
        }

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
