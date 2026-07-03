import SwiftUI

struct RoutesView: View {
    @EnvironmentObject var store: RideStore
    @AppStorage("useMetric") private var useMetric = true

    private var groups: [RouteGroup] {
        RouteMatcher.groups(from: store.rides)
    }

    var body: some View {
        NavigationView {
            Group {
                if groups.isEmpty {
                    Text("No routes yet.\nRides that follow the same road\nget grouped here automatically.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                } else {
                    List(groups) { group in
                        NavigationLink(destination: RouteDetailView(group: group)) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(group.name).font(.headline)
                                    if group.attemptCount > 1 {
                                        Text("×\(group.attemptCount)")
                                            .font(.caption.bold())
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.blue.opacity(0.15))
                                            .cornerRadius(6)
                                    }
                                }
                                Text("\(Units.distanceString(group.distanceMeters, metric: useMetric)) · PB \(Units.durationString(group.bestRide?.duration ?? 0)) · top \(Units.speedString(group.bestTopSpeed, metric: useMetric)) \(Units.speedUnit(metric: useMetric))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Routes")
        }
        .navigationViewStyle(.stack)
    }
}

struct RouteDetailView: View {
    let group: RouteGroup
    @AppStorage("useMetric") private var useMetric = true
    @AppStorage("riderName") private var riderName = ""
    @AppStorage("bikeName") private var bikeName = ""
    @State private var routeCard: RouteCardModel? = nil

    private var attempts: [Ride] {
        group.rides.sorted { $0.duration < $1.duration }
    }

    var body: some View {
        List {
            Section {
                RideMapView(points: group.referenceRide.points, brakingEvents: [])
                    .frame(height: 220)
                    .cornerRadius(12)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section("Personal best") {
                if let best = group.bestRide {
                    HStack {
                        Image(systemName: "trophy.fill").foregroundColor(.yellow)
                        VStack(alignment: .leading) {
                            Text(Units.durationString(best.duration)).font(.headline).monospacedDigit()
                            Text(best.startDate.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        Text("top \(Units.speedString(group.bestTopSpeed, metric: useMetric)) \(Units.speedUnit(metric: useMetric))")
                            .font(.subheadline).foregroundColor(.secondary)
                    }
                }
            }

            Section("Attempts (\(group.attemptCount))") {
                ForEach(attempts) { ride in
                    NavigationLink(destination: RideDetailView(ride: ride)) {
                        HStack {
                            if ride.id == group.bestRide?.id {
                                Image(systemName: "trophy.fill")
                                    .foregroundColor(.yellow)
                                    .font(.caption)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(Units.durationString(ride.duration))
                                    .monospacedDigit()
                                Text(ride.startDate.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            if let best = group.bestRide, ride.id != best.id {
                                Text("+\(String(format: "%.0f", ride.duration - best.duration)) s")
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .monospacedDigit()
                            }
                            Text("\(Units.speedString(ride.maxSpeed, metric: useMetric)) \(Units.speedUnit(metric: useMetric))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button {
                routeCard = RouteCardModel.build(group: group, riderName: riderName,
                                                 bike: bikeName, metric: useMetric)
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
        }
        .sheet(item: $routeCard) { model in
            CardShareSheet(title: "Route card", card: RouteCardView(model: model))
        }
    }
}
