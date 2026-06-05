import Combine
import CoreLocation
import Foundation
import MapKit

@MainActor
final class AddressSearchService: NSObject, ObservableObject {
    @Published private(set) var completions: [MKLocalSearchCompletion] = []

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func updateQuery(_ query: String, near coordinate: CLLocationCoordinate2D?) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completions = []
            completer.cancel()
            return
        }
        if let coordinate {
            completer.region = MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: 50_000,
                longitudinalMeters: 50_000
            )
        }
        completer.queryFragment = trimmed
    }

    func clear() {
        completions = []
        completer.cancel()
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
            completions = results
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            completions = []
        }
    }
}
