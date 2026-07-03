import SwiftUI
import Charts
import CoreLocation

struct RideDetailView: View {
    let ride: Ride
    @EnvironmentObject var store: RideStore
    @AppStorage("useMetric") private var useMetric = true
    @State private var scrubIndex: Int? = nil
    @State private var gpxURL: URL? = nil
    @State private var samples: [MetricSample] = []          // speed; also the scrub time axis
    @State private var accelSeries: [MetricSample] = []
    @State private var leanSeries: [MetricSample] = []
    @State private var elevationSeries: [MetricSample] = []
    @State private var benchmarkResults: [BenchmarkResult] = []
    @State private var mapMarkers: [RideMapMarker] = []
    @State private var chartMetric: ChartMetric = .speed

    enum ChartMetric: String, CaseIterable, Identifiable {
        case speed = "Speed"
        case accel = "Accel"
        case lean = "Lean"
        case elevation = "Elev"
        var id: String { rawValue }
    }

    private var scrubCoordinate: CLLocationCoordinate2D? {
        guard let i = scrubIndex, ride.points.indices.contains(i) else { return nil }
        let p = ride.points[i]
        return CLLocationCoordinate2D(latitude: p.latitude, longitude: p.longitude)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                RideMapView(points: ride.points,
                            markers: mapMarkers,
                            highlight: scrubCoordinate)
                    .frame(height: 280)
                    .cornerRadius(12)

                legend

                statsGrid

                chartSection

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
            if samples.isEmpty {
                samples = RideMath.speedSamples(ride.points)
                accelSeries = RideMath.accelSamples(ride.points)
                leanSeries = RideMath.leanSamples(ride.points)
                elevationSeries = RideMath.elevationSamples(ride.points)
            }
            if mapMarkers.isEmpty { buildMarkers() }
            recomputeBenchmarks()
        }
        .onChange(of: useMetric) { _ in
            recomputeBenchmarks()
            buildMarkers()   // marker subtitles carry unit strings
        }
    }

    private func recomputeBenchmarks() {
        let defs = BenchmarkDefinition.set(metric: useMetric)
        benchmarkResults = BenchmarkEngine.results(for: ride.points, definitions: defs)
    }

    // MARK: - Map markers

    private struct AllTimeBests {
        var speed = 0.0, accelG = 0.0, brakeG = 0.0, lean = 0.0
    }

    private func allTimeBests() -> AllTimeBests {
        var best = AllTimeBests()
        for r in store.rides {
            best.speed = max(best.speed, r.maxSpeed)
            let a = RideMath.analysis(r.points)
            best.accelG = max(best.accelG, a.maxAccelG)
            best.brakeG = max(best.brakeG, a.maxBrakeG)
            best.lean = max(best.lean, a.maxLeanDegrees)
        }
        return best
    }

    private func buildMarkers() {
        let unit = Units.speedUnit(metric: useMetric)
        var markers: [RideMapMarker] = []

        for e in ride.brakingEvents {
            markers.append(RideMapMarker(
                kind: .braking, latitude: e.latitude, longitude: e.longitude,
                title: "Hard braking",
                subtitle: "\(String(format: "%.2f g", e.deceleration / 9.81)) · \(Units.speedString(e.fromSpeed, metric: useMetric))→\(Units.speedString(e.toSpeed, metric: useMetric)) \(unit)"))
        }

        for e in RideMath.hardAccelEvents(ride.points) {
            let p = ride.points[e.index]
            markers.append(RideMapMarker(
                kind: .hardAccel, latitude: p.latitude, longitude: p.longitude,
                title: "Hard acceleration",
                subtitle: "\(String(format: "%.2f g", e.accel / 9.81)) · \(Units.speedString(e.fromSpeed, metric: useMetric))→\(Units.speedString(e.toSpeed, metric: useMetric)) \(unit)"))
        }

        let ex = RideMath.extremes(ride.points)
        let allTime = allTimeBests()

        func add(_ e: ExtremePoint?, isAllTime: Bool, title: String, subtitle: String) {
            guard let e = e, ride.points.indices.contains(e.index) else { return }
            let p = ride.points[e.index]
            markers.append(RideMapMarker(
                kind: isAllTime ? .allTimeRecord : .record,
                latitude: p.latitude, longitude: p.longitude,
                title: isAllTime ? "\(title) — all-time best" : "\(title) (this ride)",
                subtitle: subtitle))
        }

        add(ex.topSpeed,
            isAllTime: (ex.topSpeed?.value ?? 0) >= allTime.speed - 0.01,
            title: "Top speed",
            subtitle: "\(Units.speedString(ex.topSpeed?.value ?? 0, metric: useMetric)) \(unit)")
        add(ex.maxAccelG,
            isAllTime: (ex.maxAccelG?.value ?? 0) >= allTime.accelG - 0.001,
            title: "Best acceleration",
            subtitle: String(format: "%.2f g", ex.maxAccelG?.value ?? 0))
        add(ex.maxBrakeG,
            isAllTime: (ex.maxBrakeG?.value ?? 0) >= allTime.brakeG - 0.001,
            title: "Hardest braking",
            subtitle: String(format: "%.2f g", ex.maxBrakeG?.value ?? 0))
        add(ex.maxLean,
            isAllTime: (ex.maxLean?.value ?? 0) >= allTime.lean - 0.01,
            title: "Max lean",
            subtitle: String(format: "%.0f° %@", ex.maxLean?.value ?? 0, ex.maxLeanIsRight ? "R" : "L"))

        mapMarkers = markers
    }

    // MARK: - Sections

    private var legend: some View {
        let unit = Units.speedUnit(metric: useMetric)
        return VStack(spacing: 3) {
            LinearGradient(colors: [.green, .yellow, .red],
                           startPoint: .leading, endPoint: .trailing)
                .frame(height: 6)
                .cornerRadius(3)
            HStack {
                Text("0 \(unit)")
                Spacer()
                Text("\(Units.speedString(ride.maxSpeed / 2, metric: useMetric))")
                Spacer()
                Text("\(Units.speedString(ride.maxSpeed, metric: useMetric)) \(unit)")
            }
            .font(.caption2)
            .foregroundColor(.secondary)
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundColor(.orange)
                Text("\(ride.brakingEvents.count) hard braking")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Image(systemName: "bolt.fill")
                    .font(.caption2)
                    .foregroundColor(.green)
                Text("hard accel")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundColor(.yellow)
                Text("all-time best")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.top, 2)
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
                stat("Lean L", String(format: "%.0f°", analysis.maxLeanLeftDegrees))
                stat("Lean R", String(format: "%.0f°", analysis.maxLeanRightDegrees))
                stat("Max accel", String(format: "%.2f g", analysis.maxAccelG))
                stat("Max brake", String(format: "%.2f g", analysis.maxBrakeG))
            }
        }
    }

    // MARK: - Chart

    private var displayedSamples: [MetricSample] {
        switch chartMetric {
        case .speed: return samples
        case .accel: return accelSeries
        case .lean: return leanSeries
        case .elevation: return elevationSeries
        }
    }

    private var chartColor: Color {
        switch chartMetric {
        case .speed: return .blue
        case .accel: return .green
        case .lean: return .purple
        case .elevation: return .teal
        }
    }

    private var chartUnitLabel: String {
        switch chartMetric {
        case .speed: return Units.speedUnit(metric: useMetric)
        case .accel: return "g"
        case .lean: return "°  (R +, L −)"
        case .elevation: return useMetric ? "m" : "ft"
        }
    }

    private func chartValue(_ raw: Double) -> Double {
        switch chartMetric {
        case .speed: return useMetric ? raw * 3.6 : raw * 2.23694
        case .accel, .lean: return raw
        case .elevation: return useMetric ? raw : raw * 3.28084
        }
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Chart", selection: $chartMetric) {
                ForEach(ChartMetric.allCases) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)

            Text("Drag to see where on the map")
                .font(.caption)
                .foregroundColor(.secondary)

            if displayedSamples.isEmpty {
                Text("No elevation data on this ride — rides recorded from now on will include it.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 170)
            } else {
                Chart(displayedSamples) { s in
                    LineMark(
                        x: .value("Time", s.t),
                        y: .value("Value", chartValue(s.value))
                    )
                    .foregroundStyle(chartColor)
                    if let i = scrubIndex, i == s.id {
                        RuleMark(x: .value("Time", s.t))
                            .foregroundStyle(.orange)
                    }
                }
                .chartYAxisLabel(chartUnitLabel)
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
                            )
                    }
                }
            }
        }
    }

    /// Binary search over the speed samples (always full-length, same time
    /// axis as every other series).
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
        VStack(alignment: .leading, spacing: 8) {
            Text("Timed runs (this ride)")
                .font(.headline)
            if benchmarkResults.isEmpty {
                Text("No complete runs detected on this ride.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                ForEach(benchmarkResults) { r in
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
