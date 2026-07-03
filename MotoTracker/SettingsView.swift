import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var recorder: RideRecorder
    @EnvironmentObject var store: RideStore
    @State private var demoAdded = false
    @AppStorage("useMetric") private var useMetric = true
    @AppStorage("autoRecord") private var autoRecord = false

    var body: some View {
        NavigationView {
            Form {
                Section("Units") {
                    Picker("Speed units", selection: $useMetric) {
                        Text("km/h").tag(true)
                        Text("mph").tag(false)
                    }
                    .pickerStyle(.segmented)
                    Text("Also switches the timed-run set: km/h mode times 0–100, 0–200, 60–120, 100–200 km/h and 400 m; mph mode times 0–30, 0–60, 20–80, 60–130 mph, 1/8 and 1/4 mile.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                Section("Auto-record") {
                    Toggle("Record rides automatically", isOn: $autoRecord)
                        .onChange(of: autoRecord) { recorder.setAutoMode($0) }
                    Text("Uses cell-tower wake-ups, so it costs almost no battery while parked. When movement is detected, GPS checks your speed for up to 90 s; sustained riding speed starts a recording, and 3 minutes stationary saves it and goes back to sleep.\n\nRequires location access set to \u{201C}Always\u{201D} (iOS will ask). Note it can't tell a motorbike from a car — delete trips you don't want. Also recorded rides start from the first cell-tower wake-up, so the very first few hundred meters may be missed.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                Section("How it works") {
                    Text("Route line color shows speed: green = slow, red = fast, relative to that ride's top speed. Orange pins mark hard braking (deceleration over 3 m/s²). Lean angle and G-force are estimated from GPS, so they work regardless of how the phone is mounted. Rides that follow the same road are grouped automatically in Routes, with a personal best per route.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                Section("Testing") {
                    Button(demoAdded ? "Demo rides added" : "Add demo rides") {
                        DemoRide.addDemoRides(to: store)
                        demoAdded = true
                    }
                    .disabled(demoAdded)
                    Text("Adds two fake attempts of the same route \u{2014} with a 0\u{2013}100 sprint, hard braking, corners and a ~160 km/h top speed \u{2014} so History, Routes (PB), Records and the speed graph all have data. Swipe-delete them in History when done.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                Section {
                    Text("Timed runs and top-speed records are for closed roads and track use.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
        .navigationViewStyle(.stack)
    }
}
