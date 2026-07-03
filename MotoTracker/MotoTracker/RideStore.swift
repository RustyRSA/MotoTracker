import Foundation

final class RideStore: ObservableObject {
    @Published var rides: [Ride] = []

    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("rides.json")
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
        rides = (try? decoder.decode([Ride].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(rides) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
