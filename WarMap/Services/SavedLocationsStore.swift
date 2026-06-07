import Foundation

@MainActor
final class SavedLocationsStore: ObservableObject {
    @Published private(set) var locations: [SavedLocation] = []

    private let storageKey = "saved-locations"

    init() {
        load()
    }

    func add(name: String, place: MapPlace) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        locations.append(SavedLocation(name: trimmed, place: place))
        locations.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        save()
    }

    func delete(at offsets: IndexSet) {
        locations.remove(atOffsets: offsets)
        save()
    }

    func delete(id: UUID) {
        locations.removeAll { $0.id == id }
        save()
    }

    private func load() {
        guard
            let data = UserDefaults.standard.data(forKey: storageKey),
            let decoded = try? JSONDecoder().decode([SavedLocation].self, from: data)
        else {
            locations = []
            return
        }
        locations = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(locations) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
