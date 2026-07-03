import Foundation

final class RideStore: ObservableObject {
    @Published var rides: [Ride] = []

    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("rides.json")
    }

    private var backupURL: URL {
        fileURL.deletingLastPathComponent().appendingPathComponent("rides.json.bak")
    }

    init() { load() }

    func add(_ ride: Ride) {
        rides.insert(ride, at: 0)
        save()
    }

    func delete(at offsets: IndexSet) {
        rides.remove(atOffsets: offsets)
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([Ride].self, from: data) {
            rides = decoded
        } else {
            // Corrupt or unreadable schema: preserve the raw bytes before anything
            // can overwrite rides.json, so history is recoverable instead of lost.
            try? data.write(to: backupURL, options: .atomic)
            rides = []
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(rides) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
