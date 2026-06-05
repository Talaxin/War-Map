import CoreLocation
import Foundation
import MapKit

enum RouteDirectionsError: LocalizedError {
    case missingEndpoints
    case noRoute

    var errorDescription: String? {
        switch self {
        case .missingEndpoints:
            return "Set a start and destination first."
        case .noRoute:
            return "No driving route found between these locations."
        }
    }
}

@MainActor
final class RouteDirectionsService {
    func calculateRoute(from start: MapPlace, to destination: MapPlace) async throws -> MKRoute {
        let request = MKDirections.Request()
        request.source = mapItem(for: start)
        request.destination = mapItem(for: destination)
        request.transportType = .automobile
        request.requestsAlternateRoutes = false

        let directions = MKDirections(request: request)
        let response = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<MKDirections.Response, Error>) in
            directions.calculate { response, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let response {
                    continuation.resume(returning: response)
                } else {
                    continuation.resume(throwing: RouteDirectionsError.noRoute)
                }
            }
        }

        guard let route = response.routes.first else {
            throw RouteDirectionsError.noRoute
        }
        return route
    }

    private func mapItem(for place: MapPlace) -> MKMapItem {
        let placemark = MKPlacemark(coordinate: place.coordinate)
        let item = MKMapItem(placemark: placemark)
        item.name = place.title
        return item
    }
}
