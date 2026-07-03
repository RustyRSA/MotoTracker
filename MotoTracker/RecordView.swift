import SwiftUI

struct RecordView: View {
    @EnvironmentObject var recorder: RideRecorder
    @EnvironmentObject var store: RideStore
    @AppStorage("useMetric") private var useMetric = true

    var body: some View {
        NavigationView {
            VStack(spacing: 10) {
                VStack(spacing: 0) {
                    Text(Units.speedString(recorder.currentSpeed, metric: useMetric))
                        .font(.system(size: 80, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(Units.speedUnit(metric: useMetric))
                        .font(.title3)
                        .foregroundColor(.secondary)
                }

                HStack {
                    stat("Distance", Units.distanceString(recorder.distance, metric: useMetric))
                    if recorder.isRecording, let start = recorder.startDate {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            stat("Time", Units.durationString(context.date.timeIntervalSince(start)))
                        }
                    } else {
                        stat("Time", "00:00:00")
                    }
                    stat("Top", Units.speedString(recorder.topSpeed, metric: useMetric))
                }

                HStack {
                    stat("Lean", String(format: "%.0f°", recorder.currentLean))
                    stat("G", String(format: "%+.2f", recorder.currentG))
                    stat("Braking", "\(recorder.brakingEvents.count)")
                }

                RideMapView(points: recorder.points,
                            brakingEvents: recorder.brakingEvents,
                            followsUser: true)
                    .cornerRadius(12)

                Button {
                    if recorder.isRecording {
                        recorder.stopRide()
                    } else {
                        recorder.start()
                    }
                } label: {
                    Text(recorder.isRecording ? "Stop Ride" : "Start Ride")
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(recorder.isRecording ? Color.red : Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(14)
                }

                if recorder.autoArmed && !recorder.isRecording {
                    Label("Auto-record armed — rides start and save themselves",
                          systemImage: "bolt.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .navigationTitle("MotoTracker")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { recorder.requestPermission() }
            .alert("Location access denied", isPresented: $recorder.authorizationDenied) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Enable location access for MotoTracker in Settings to record rides.")
            }
        }
        .navigationViewStyle(.stack)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack {
            Text(value).font(.headline).monospacedDigit()
            Text(label).font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
