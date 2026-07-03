import SwiftUI
import Charts
import CoreLocation

struct RideDetailView: View {
    let ride: Ride
    @AppStorage("useMetric") private var useMetric = true
    @State private var scrubIndex: Int? = nil
    @State private var gpxURL: URL? = nil

    private var samples: [SpeedSample] { RideMath.speedSamples(ride.points) }

    private var scrubCoordinate: CLLocationCoordinate2D? {
        guard let i = scrubIndex, ride.points.indices.contains(i) else { return nil }
        let p = ride.points[i]
        return CLLocationCoordinate2D(latitude: p.latitude, longitude: p.longitude)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                RideMapView(points: ride.points,
                            brakingEvents: ride.brakingEvents,
                            highlight: scrubCoordinate)
                    .frame(height: 280)
                    .cornerRadius(12)

                legend

                statsGrid

                speedChart

                benchmarksSection
            }
            .padding()
        }
        .navigationTitle(ride.startDate.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let url = gpxURL {
                ShareLink(item: url) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .onAppear {
            if gpxURL == nil { gpxURL = GPXExporter.writeTempFile(for: ride) }
        }
    }

    private var legend: some View {
        HStack(spacing: 8) {
            Text("Slow").font(.caption2).foregroundColor(.secondary)
            LinearGradient(colors: [.green, .yellow, .red],
                           startPoint: .leading, endPoint: .trailing)
                .frame(height: 6)
                .cornerRadius(3)
            Text("Fast").font(.caption2).foregroundColor(.secondary)
            Spacer(minLength: 12)
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundColor(.orange)
            Text("\(ride.brakingEvents.count) hard braking")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 4)
    }

    private var statsGrid: some View {
        let analysis = RideMath.analysis(ride.points)
        return VStack(spacing: 10) {
            HStack {
                stat("Distance", Units.distanceString(ride.distanceMeters, metric: useMetric))
                stat("Time", Units.durationString(ride.duration))
                stat("Avg", Units.speedString(ride.avgMovingSpeed, metric: useMetric))
                stat("Top", Units.speedString(ride.maxSpeed, metric: useMetric))
            }
            HStack {
                stat("Max lean", String(format: "%.0f°", analysis.maxLeanDegrees))
                stat("Max accel", String(format: "%.2f g", analysis.maxAccelG))
                stat("Max brake", String(format: "%.2f g", analysis.maxBrakeG))
            }
        }
    }

    private var speedChart: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Speed — drag to see where on the map")
                .font(.caption)
                .foregroundColor(.secondary)
            Chart(samples) { s in
                LineMark(
                    x: .value("Time", s.t),
                    y: .value("Speed", useMetric ? s.speed * 3.6 : s.speed * 2.23694)
                )
                .foregroundStyle(.blue)
                if let i = scrubIndex, i == s.id {
                    RuleMark(x: .value("Time", s.t))
                        .foregroundStyle(.orange)
                }
            }
            .chartYAxisLabel(Units.speedUnit(metric: useMetric))
            .frame(height: 170)
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let origin = geo[proxy.plotAreaFrame].origin
                                    if let t: Double = proxy.value(atX: value.location.x - origin.x) {
                                        scrubIndex = nearestSampleIndex(to: t)
                                    }
                                }
                                .onEnded { _ in scrubIndex = nil }
                        )
                }
            }
        }
    }

    private func nearestSampleIndex(to t: Double) -> Int? {
        guard !samples.isEmpty else { return nil }
        var lo = 0, hi = samples.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if samples[mid].t < t { lo = mid + 1 } else { hi = mid }
        }
        return samples[lo].id
    }

    private var benchmarksSection: some View {
        let defs = BenchmarkDefinition.set(metric: useMetric)
        let results = BenchmarkEngine.results(for: ride.points, definitions: defs)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Timed runs (this ride)")
                .font(.headline)
            if results.isEmpty {
                Text("No complete runs detected on this ride.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                ForEach(results) { r in
                    HStack {
                        Text(r.definition.name)
                        Spacer()
                        Text(benchmarkValue(r))
                            .monospacedDigit()
                            .bold()
                    }
                    .font(.subheadline)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private func benchmarkValue(_ r: BenchmarkResult) -> String {
        if case .standingDistance = r.definition.kind {
            return String(format: "%.2f s @ %@ %@", r.seconds,
                          Units.speedString(r.endSpeed, metric: useMetric),
                          Units.speedUnit(metric: useMetric))
        }
        return String(format: "%.2f s", r.seconds)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack {
            Text(value).font(.subheadline.bold()).monospacedDigit()
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
