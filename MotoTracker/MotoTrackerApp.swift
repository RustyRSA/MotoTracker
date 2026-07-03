import SwiftUI

@main
struct MotoTrackerApp: App {
    @StateObject private var store: RideStore
    @StateObject private var recorder: RideRecorder

    init() {
        let store = RideStore()
        let recorder = RideRecorder()
        recorder.store = store
        // Re-arms auto-record after any launch — including when iOS relaunches
        // the app in the background for a significant location change.
        recorder.resumeAutoModeIfEnabled()
        _store = StateObject(wrappedValue: store)
        _recorder = StateObject(wrappedValue: recorder)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(recorder)
        }
    }
}

struct ContentView: View {
    var body: some View {
        TabView {
            RecordView()
                .tabItem { Label("Ride", systemImage: "speedometer") }
            RideListView()
                .tabItem { Label("History", systemImage: "clock") }
            RoutesView()
                .tabItem { Label("Routes", systemImage: "map") }
            RecordsView()
                .tabItem { Label("Records", systemImage: "trophy") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
