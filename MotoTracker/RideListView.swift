import SwiftUI

struct RideListView: View {
    @EnvironmentObject var store: RideStore
    @AppStorage("useMetric") private var useMetric = true

    var body: some View {
        NavigationView {
            Group {
                if store.rides.isEmpty {
                    Text("No rides yet.\nStart one from the Ride tab.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                } else {
                    List {
                        ForEach(store.rides) { ride in
                            NavigationLink(destination: RideDetailView(ride: ride)) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(ride.startDate.formatted(date: .abbreviated, time: .shortened))
                                        .font(.headline)
                                    Text("\(Units.distanceString(ride.distanceMeters, metric: useMetric)) · \(Units.durationString(ride.duration)) · max \(Units.speedString(ride.maxSpeed, metric: useMetric)) \(Units.speedUnit(metric: useMetric))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .onDelete { store.delete(at: $0) }
                    }
                }
            }
            .navigationTitle("History")
        }
        .navigationViewStyle(.stack)
    }
}
