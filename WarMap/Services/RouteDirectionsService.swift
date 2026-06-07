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
        preferences: RoutePreferences,
        discoverNewRoadAlternates: Bool = false
    ) async throws -> MKRoute {
        let routes = try await calculateRoutes(
            from: start,
            to: destination,
            preferences: preferences,
            discoverNewRoadAlternates: discoverNewRoadAlternates
        )
        guard let route = routes.first else {
            throw RouteDirectionsError.noRoute
        }
        return route
    }

    func calculateRoutes(
        from start: MapPlace,
        to destination: MapPlace,
        preferences: RoutePreferences,
        discoverNewRoadAlternates: Bool = false
    ) async throws -> [MKRoute] {
        var routes = try await fetchPrimaryRoutes(from: start, to: destination, preferences: preferences)

        if discoverNewRoadAlternates {
            var discoveryPreferences: [RoutePreferences] = []

            if preferences.allowHighways {
                var avoidHighways = preferences
                avoidHighways.allowHighways = false
                discoveryPreferences.append(avoidHighways)
            }
            if preferences.allowTollRoads {
                var avoidTolls = preferences
                avoidTolls.allowTollRoads = false
                discoveryPreferences.append(avoidTolls)
            }
            if preferences.allowHighways, preferences.allowTollRoads {
                var scenic = preferences
                scenic.allowHighways = false
                scenic.allowTollRoads = false
                discoveryPreferences.append(scenic)
            }
            if preferences.allowFerries {
                var avoidFerries = preferences
                avoidFerries.allowFerries = false
                discoveryPreferences.append(avoidFerries)
            }
            if !preferences.allowHighways {
                var preferHighways = preferences
                preferHighways.allowHighways = true
                discoveryPreferences.append(preferHighways)
            }

            for variant in discoveryPreferences {
                if let alternates = try? await fetchRoutes(
                    from: start,
                    to: destination,
                    preferences: variant
                ) {
                    routes.append(contentsOf: alternates)
                }
            }
        }

        routes = routes.filter { routeMatchesEndpoints($0, start: start.coordinate, destination: destination.coordinate) }
        routes = deduplicatedRoutes(routes)
        routes.sort { $0.expectedTravelTime < $1.expectedTravelTime }
        guard !routes.isEmpty else {
            throw RouteDirectionsError.noRoute
        }
        return routes
    }

    /// Primary Apple Maps alternates for the user's preferences.
    func fetchPrimaryRoutes(
        from start: MapPlace,
        to destination: MapPlace,
        preferences: RoutePreferences
    ) async throws -> [MKRoute] {
        try await fetchRoutes(from: start, to: destination, preferences: preferences)
    }

    private func fetchRoutes(
        from start: MapPlace,
        to destination: MapPlace,
        preferences: RoutePreferences
    ) async throws -> [MKRoute] {
        let request = MKDirections.Request()
        request.source = mapItem(for: start)
        request.destination = mapItem(for: destination)
        request.transportType = .automobile
        request.requestsAlternateRoutes = true

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
        return routes
    }

    private func routeMatchesEndpoints(
        _ route: MKRoute,
        start: CLLocationCoordinate2D,
        destination: CLLocationCoordinate2D
    ) -> Bool {
        guard route.polyline.pointCount >= 2 else { return false }

        let points = route.polyline.points()
        let routeStart = points[0].coordinate
        let routeEnd = points[route.polyline.pointCount - 1].coordinate
        let maxGap: CLLocationDistance = 600

        let startGap = CLLocation(latitude: routeStart.latitude, longitude: routeStart.longitude)
            .distance(from: CLLocation(latitude: start.latitude, longitude: start.longitude))
        let endGap = CLLocation(latitude: routeEnd.latitude, longitude: routeEnd.longitude)
            .distance(from: CLLocation(latitude: destination.latitude, longitude: destination.longitude))

        return startGap <= maxGap && endGap <= maxGap
    }

    private func deduplicatedRoutes(_ routes: [MKRoute]) -> [MKRoute] {
        var unique: [MKRoute] = []
        for route in routes {
            let duplicate = unique.contains { existing in
                abs(existing.distance - route.distance) < 150
                    && abs(existing.expectedTravelTime - route.expectedTravelTime) < 30
            }
            if !duplicate {
                unique.append(route)
            }
        }
        return unique
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
