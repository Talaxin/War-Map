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
    func calculateRoute(
        from start: MapPlace,
        to destination: MapPlace,
        preferences: RoutePreferences
    ) async throws -> MKRoute {
        let request = MKDirections.Request()
        request.source = mapItem(for: start)
        request.destination = mapItem(for: destination)
        request.transportType = .automobile
        request.requestsAlternateRoutes = false

        if #available(iOS 16.0, *) {
            request.highwayPreference = preferences.allowHighways ? .any : .avoid
            request.tollPreference = preferences.allowTollRoads ? .any : .avoid
        }

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

        var routes = response.routes
        if !preferences.allowFerries {
            routes = routes.filter { !routeUsesFerries($0) }
        }
        if !preferences.allowCrossBorder {
            routes = routes.filter { route in
                !routeCrossesBorder(route, start: start, destination: destination)
            }
        }

        guard let route = routes.first else {
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

    private func routeUsesFerries(_ route: MKRoute) -> Bool {
        let ferryKeywords = ["ferry", "boat"]
        return route.steps.contains { step in
            let text = step.instructions.lowercased()
            return ferryKeywords.contains { text.contains($0) }
        }
    }

    private func routeCrossesBorder(_ route: MKRoute, start: MapPlace, destination: MapPlace) -> Bool {
        let startCountry = start.subtitle?.countryCode
        let destCountry = destination.subtitle?.countryCode
        if let startCountry, let destCountry, startCountry != destCountry {
            return true
        }
        return false
    }
}

private extension String {
    var countryCode: String? {
        let upper = uppercased()
        if upper.contains("CANADA") || upper.hasSuffix(" BC") || upper.contains(", CA") { return "CA" }
        if upper.contains("UNITED STATES") || upper.contains(", US") || upper.contains(", USA") { return "US" }
        if upper.contains("MEXICO") || upper.contains(", MX") { return "MX" }
        return nil
    }
}
