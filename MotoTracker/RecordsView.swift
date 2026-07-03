import SwiftUI

struct RecordsView: View {
    @EnvironmentObject var store: RideStore
    @AppStorage("useMetric") private var useMetric = true
    @AppStorage("riderName") private var riderName = ""
    @AppStorage("bikeName") private var bikeName = ""
    @State private var profileCard: ProfileCardModel? = nil

    struct Trophy: Identifiable {
        let id: String
        let name: String
        let value: String
        let date: Date?
    }

    var body: some View {
        NavigationView {
            Group {
                if store.rides.isEmpty {
                    Text("No records yet.\nGo ride.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                } else {
                    List {
                        Section("Rider") {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(riderName.isEmpty ? "Unnamed rider" : riderName)
                                        .font(.headline)
                                    Text(bikeName.isEmpty ? "Set name and bike in Settings" : bikeName)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Button {
                                    profileCard = ProfileCardModel.build(
                                        name: riderName, bike: bikeName,
                                        rides: store.rides, metric: useMetric)
                                } label: {
                                    Label("Card", systemImage: "square.and.arrow.up")
                                        .font(.subheadline)
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding(.vertical, 2)
                        }
                        Section("Acceleration — all-time best") {
                            ForEach(accelerationTrophies) { trophyRow($0) }
                        }
                        Section("Records") {
                            ForEach(generalTrophies) { trophyRow($0) }
                        }
                        Section("Totals") {
                            ForEach(totals) { trophyRow($0) }
                        }
                    }
                }
            }
            .navigationTitle("Records")
            .sheet(item: $profileCard) { model in
                CardShareSheet(title: "Profile card", card: ProfileCardView(model: model))
            }
        }
        .navigationViewStyle(.stack)
    }

    private func trophyRow(_ t: Trophy) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(t.name).font(.subheadline)
                if let date = t.date {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
            Spacer()
            Text(t.value).bold().monospacedDigit()
        }
    }

    private var accelerationTrophies: [Trophy] {
        let defs = BenchmarkDefinition.set(metric: useMetric)
        return defs.map { def in
            var best: (BenchmarkResult, Date)? = nil
            for ride in store.rides {
                if let r = BenchmarkEngine.results(for: ride.points, definitions: [def]).first {
                    if best == nil || r.seconds < best!.0.seconds {
                        best = (r, ride.startDate)
                    }
                }
            }
            if let (r, date) = best {
                let value: String
                if case .standingDistance = def.kind {
                    value = String(format: "%.2f s @ %@ %@", r.seconds,
                                   Units.speedString(r.endSpeed, metric: useMetric),
                                   Units.speedUnit(metric: useMetric))
                } else {
                    value = String(format: "%.2f s", r.seconds)
                }
                return Trophy(id: def.id, name: def.name, value: value, date: date)
            }
            return Trophy(id: def.id, name: def.name, value: "—", date: nil)
        }
    }

    private var generalTrophies: [Trophy] {
        var trophies: [Trophy] = []

        if let fastest = store.rides.max(by: { $0.maxSpeed < $1.maxSpeed }) {
            trophies.append(Trophy(
                id: "topspeed", name: "Top speed",
                value: "\(Units.speedString(fastest.maxSpeed, metric: useMetric)) \(Units.speedUnit(metric: useMetric))",
                date: fastest.startDate))
        }

        var bestLeanL: (Double, Date)? = nil
        var bestLeanR: (Double, Date)? = nil
        var bestAccel: (Double, Date)? = nil
        var bestBrake: (Double, Date)? = nil
        for ride in store.rides {
            let a = RideMath.analysis(ride.points)
            if bestLeanL == nil || a.maxLeanLeftDegrees > bestLeanL!.0 { bestLeanL = (a.maxLeanLeftDegrees, ride.startDate) }
            if bestLeanR == nil || a.maxLeanRightDegrees > bestLeanR!.0 { bestLeanR = (a.maxLeanRightDegrees, ride.startDate) }
            if bestAccel == nil || a.maxAccelG > bestAccel!.0 { bestAccel = (a.maxAccelG, ride.startDate) }
            if bestBrake == nil || a.maxBrakeG > bestBrake!.0 { bestBrake = (a.maxBrakeG, ride.startDate) }
        }
        if let (v, d) = bestLeanL {
            trophies.append(Trophy(id: "leanL", name: "Max lean left", value: String(format: "%.0f°", v), date: d))
        }
        if let (v, d) = bestLeanR {
            trophies.append(Trophy(id: "leanR", name: "Max lean right", value: String(format: "%.0f°", v), date: d))
        }
        if let (v, d) = bestAccel {
            trophies.append(Trophy(id: "accelg", name: "Max acceleration", value: String(format: "%.2f g", v), date: d))
        }
        if let (v, d) = bestBrake {
            trophies.append(Trophy(id: "brakeg", name: "Max braking", value: String(format: "%.2f g", v), date: d))
        }
        if let longest = store.rides.max(by: { $0.distanceMeters < $1.distanceMeters }) {
            trophies.append(Trophy(
                id: "longest", name: "Longest ride",
                value: Units.distanceString(longest.distanceMeters, metric: useMetric),
                date: longest.startDate))
        }
        return trophies
    }

    private var totals: [Trophy] {
        let totalDist = store.rides.map(\.distanceMeters).reduce(0, +)
        let totalTime = store.rides.map(\.duration).reduce(0, +)
        return [
            Trophy(id: "rides", name: "Total rides", value: "\(store.rides.count)", date: nil),
            Trophy(id: "dist", name: "Total distance",
                   value: Units.distanceString(totalDist, metric: useMetric), date: nil),
            Trophy(id: "time", name: "Total time",
                   value: Units.durationString(totalTime), date: nil),
        ]
    }
}
