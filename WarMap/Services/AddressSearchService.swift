import Combine
import CoreLocation
import Foundation
import MapKit

@MainActor
final class AddressSearchService: NSObject, ObservableObject {
    @Published private(set) var completions: [MKLocalSearchCompletion] = []

    private let completer = MKLocalSearchCompleter()
    private var localityHint: String?

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func updateQuery(_ query: String, near coordinate: CLLocationCoordinate2D?, localityHint: String?) {
        self.localityHint = localityHint
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completions = []
            completer.cancel()
            return
        }
        if let coordinate {
            completer.region = MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: 20_000,
                longitudinalMeters: 20_000
            )
        }
        completer.queryFragment = trimmed
    }

    func clear() {
        completions = []
        completer.cancel()
        localityHint = nil
    }

    func resolve(_ completion: MKLocalSearchCompletion) async throws -> MapPlace {
        let request = MKLocalSearch.Request(completion: completion)
        let response = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<MKLocalSearch.Response, Error>) in
            MKLocalSearch(request: request).start { response, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let response {
                    continuation.resume(returning: response)
                } else {
                    continuation.resume(throwing: AddressSearchError.noResults)
                }
            }
        }
        guard let item = response.mapItems.first else {
            throw AddressSearchError.noResults
        }
        let placemark = item.placemark
        guard placemark.location != nil else {
            throw AddressSearchError.noResults
        }
        return MapPlace(
            title: item.name ?? completion.title,
            subtitle: completion.subtitle,
            coordinate: placemark.coordinate
        )
    }

    private func filterLocal(_ results: [MKLocalSearchCompletion]) -> [MKLocalSearchCompletion] {
        guard let hint = localityHint?.trimmingCharacters(in: .whitespacesAndNewlines), !hint.isEmpty else {
            return results
        }
        let tokens = localityTokens(from: hint)
        guard !tokens.isEmpty else { return results }

        let local = results.filter { completion in
            let haystack = "\(completion.title) \(completion.subtitle)".lowercased()
            return tokens.contains { haystack.contains($0) }
        }
        if local.isEmpty {
            return Array(results.prefix(6))
        }
        let nonLocal = results.filter { completion in
            !local.contains(where: { $0.title == completion.title && $0.subtitle == completion.subtitle })
        }
        return local + Array(nonLocal.prefix(3))
    }

    private func localityTokens(from hint: String) -> [String] {
        let parts = hint
            .lowercased()
            .components(separatedBy: CharacterSet(charactersIn: ",·"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count > 2 }
        return Array(Set(parts)).prefix(4).map { $0 }
    }
}

enum AddressSearchError: LocalizedError {
    case noResults

    var errorDescription: String? {
        switch self {
        case .noResults:
            return "No location found for that search."
        }
    }
}

extension AddressSearchService: MKLocalSearchCompleterDelegate {
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = completer.results
        Task { @MainActor in
            completions = filterLocal(results)
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            completions = []
        }
    }
}
