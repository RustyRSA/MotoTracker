import SwiftUI

// Local rider profile cards — stage 1 of profiles. Everything stays on-device;
// "sharing" renders a PNG the owner can send wherever they like.

// MARK: - Card data

struct ProfileCardModel: Identifiable {
    let id = UUID()
    let name: String
    let bike: String
    let rideCount: Int
    let totalDistance: Double   // m
    let totalTime: TimeInterval
    let topSpeed: Double        // m/s
    let maxLeanL: Double        // degrees
    let maxLeanR: Double        // degrees
    let metric: Bool

    static func build(name: String, bike: String, rides: [Ride], metric: Bool) -> ProfileCardModel {
        var leanL = 0.0, leanR = 0.0
        for ride in rides {
            let a = RideMath.analysis(ride.points)
            leanL = max(leanL, a.maxLeanLeftDegrees)
            leanR = max(leanR, a.maxLeanRightDegrees)
        }
        return ProfileCardModel(
            name: name, bike: bike,
            rideCount: rides.count,
            totalDistance: rides.map(\.distanceMeters).reduce(0, +),
            totalTime: rides.map(\.duration).reduce(0, +),
            topSpeed: rides.map(\.maxSpeed).max() ?? 0,
            maxLeanL: leanL, maxLeanR: leanR,
            metric: metric)
    }
}

struct RouteCardModel: Identifiable {
    let id = UUID()
    let routeName: String
    let riderName: String
    let bike: String
    let attemptCount: Int
    let distance: Double        // m
    let bestDuration: TimeInterval
    let topSpeed: Double        // m/s
    let bestDate: Date?
    let metric: Bool

    static func build(group: RouteGroup, riderName: String, bike: String, metric: Bool) -> RouteCardModel {
        RouteCardModel(
            routeName: group.name,
            riderName: riderName, bike: bike,
            attemptCount: group.attemptCount,
            distance: group.distanceMeters,
            bestDuration: group.bestRide?.duration ?? 0,
            topSpeed: group.bestTopSpeed,
            bestDate: group.bestRide?.startDate,
            metric: metric)
    }
}

// MARK: - Card views
// Fixed dark palette (no dynamic colors) so the rendered image looks the
// same regardless of the system light/dark setting.

private struct CardChrome<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            content
            HStack {
                Image(systemName: "speedometer")
                Text("MotoTracker")
                Spacer()
                Text(Date().formatted(date: .abbreviated, time: .omitted))
            }
            .font(.caption2)
            .foregroundColor(.white.opacity(0.45))
        }
        .padding(20)
        .frame(width: 360, alignment: .leading)
        .background(
            LinearGradient(colors: [Color(red: 0.13, green: 0.14, blue: 0.18),
                                    Color(red: 0.05, green: 0.05, blue: 0.07)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .cornerRadius(20)
    }
}

private struct CardStat: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.headline.monospacedDigit()).foregroundColor(.white)
            Text(label).font(.caption2).foregroundColor(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ProfileCardView: View {
    let model: ProfileCardModel

    var body: some View {
        CardChrome {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.name.isEmpty ? "Rider" : model.name)
                    .font(.title2.bold()).foregroundColor(.white)
                if !model.bike.isEmpty {
                    Text(model.bike).font(.subheadline).foregroundColor(.orange)
                }
            }
            HStack {
                CardStat(label: "Rides", value: "\(model.rideCount)")
                CardStat(label: "Distance", value: Units.distanceString(model.totalDistance, metric: model.metric))
                CardStat(label: "Time", value: Units.durationString(model.totalTime))
            }
            HStack {
                CardStat(label: "Top speed",
                         value: "\(Units.speedString(model.topSpeed, metric: model.metric)) \(Units.speedUnit(metric: model.metric))")
                CardStat(label: "Lean L", value: String(format: "%.0f°", model.maxLeanL))
                CardStat(label: "Lean R", value: String(format: "%.0f°", model.maxLeanR))
            }
        }
    }
}

struct RouteCardView: View {
    let model: RouteCardModel

    var body: some View {
        CardChrome {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(model.routeName).font(.title3.bold()).foregroundColor(.white)
                    if model.attemptCount > 1 {
                        Text("×\(model.attemptCount)")
                            .font(.caption.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.35))
                            .cornerRadius(6)
                    }
                }
                let rider = [model.riderName, model.bike].filter { !$0.isEmpty }.joined(separator: " · ")
                if !rider.isEmpty {
                    Text(rider).font(.subheadline).foregroundColor(.orange)
                }
            }
            HStack {
                CardStat(label: "Route", value: Units.distanceString(model.distance, metric: model.metric))
                CardStat(label: "Best time", value: Units.durationString(model.bestDuration))
                CardStat(label: "Top speed",
                         value: "\(Units.speedString(model.topSpeed, metric: model.metric)) \(Units.speedUnit(metric: model.metric))")
            }
            if let date = model.bestDate {
                Text("PB set \(date.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption).foregroundColor(.white.opacity(0.55))
            }
        }
    }
}

// MARK: - Share sheet

/// Shows a card and a ShareLink for its rendered PNG. Rendering happens once,
/// when the sheet appears — not per body evaluation.
struct CardShareSheet<Card: View>: View {
    let title: String
    let card: Card
    @Environment(\.dismiss) private var dismiss
    @State private var rendered: Image? = nil

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                card
                if let img = rendered {
                    ShareLink(item: img, preview: SharePreview(title, image: img)) {
                        Label("Share as image", systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                }
                Spacer()
            }
            .padding(.top, 24)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                guard rendered == nil else { return }
                let cardCopy = card
                Task { @MainActor in
                    let renderer = ImageRenderer(content: cardCopy)
                    renderer.scale = 3
                    if let ui = renderer.uiImage {
                        rendered = Image(uiImage: ui)
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}
