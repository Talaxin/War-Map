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
        var routes = try await fetchRoutes(from: start, to: destination, preferences: preferences)

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

            for variant in discoveryPreferences {
                if let alternates = try? await fetchRoutes(
                    from: start,
                    to: destination,
                    preferences: variant
                ) {
                    routes.append(contentsOf: alternates)
                }
            }

            if let fastest = routes.min(by: { $0.expectedTravelTime < $1.expectedTravelTime }) {
                let offsets = await fetchOffsetEndpointRoutes(
                    from: start,
                    to: destination,
                    preferences: preferences,
                    reference: fastest
                )
                routes.append(contentsOf: offsets)
            }
        }

        routes = deduplicatedRoutes(routes)
        guard !routes.isEmpty else {
            throw RouteDirectionsError.noRoute
        }
        return routes
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

    /// Request real MapKit routes from points offset perpendicular to the fastest path endpoints.
    private func fetchOffsetEndpointRoutes(
        from start: MapPlace,
        to destination: MapPlace,
        preferences: RoutePreferences,
        reference: MKRoute
    ) async -> [MKRoute] {
        guard reference.polyline.pointCount >= 2 else { return [] }

        let points = reference.polyline.points()
        let routeStart = points[0].coordinate
        let routeEnd = points[reference.polyline.pointCount - 1].coordinate
        let startBearing = bearingDegrees(from: routeStart, to: points[1].coordinate)
        let endBearing = bearingDegrees(
            from: points[reference.polyline.pointCount - 2].coordinate,
            to: routeEnd
        )

        let offsetsMeters: [CLLocationDistance] = [2_500, 5_000, 8_000]
        let bearings: [Double] = [90, -90]
        var routes: [MKRoute] = []
        let maxDetourTime = reference.expectedTravelTime * 1.8

        for meters in offsetsMeters {
            for delta in bearings {
                let offsetStart = offsetCoordinate(routeStart, bearingDegrees: startBearing + delta, meters: meters)
                let offsetEnd = offsetCoordinate(routeEnd, bearingDegrees: endBearing + delta, meters: meters)

                let viaStart = MapPlace(title: start.title, subtitle: start.subtitle, coordinate: offsetStart)
                let viaEnd = MapPlace(title: destination.title, subtitle: destination.subtitle, coordinate: offsetEnd)

                if let startRoutes = try? await fetchRoutes(from: viaStart, to: destination, preferences: preferences),
                   let best = startRoutes.min(by: { $0.expectedTravelTime < $1.expectedTravelTime }),
                   best.expectedTravelTime <= maxDetourTime {
                    routes.append(best)
                }

                if let endRoutes = try? await fetchRoutes(from: start, to: viaEnd, preferences: preferences),
                   let best = endRoutes.min(by: { $0.expectedTravelTime < $1.expectedTravelTime }),
                   best.expectedTravelTime <= maxDetourTime {
                    routes.append(best)
                }
            }
        }

        return routes
    }

    private func deduplicatedRoutes(_ routes: [MKRoute]) -> [MKRoute] {
        var unique: [MKRoute] = []
        for route in routes {
            let duplicate = unique.contains { existing in
                abs(existing.distance - route.distance) < 250
                    && abs(existing.expectedTravelTime - route.expectedTravelTime) < 90
            }
            if !duplicate {
                unique.append(route)
            }
        }
        return unique
    }

    private func bearingDegrees(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> Double {
        let lat1 = start.latitude * .pi / 180
        let lat2 = end.latitude * .pi / 180
        let deltaLon = (end.longitude - start.longitude) * .pi / 180
        let y = sin(deltaLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
        let bearing = atan2(y, x) * 180 / .pi
        return bearing >= 0 ? bearing : bearing + 360
    }

    private func offsetCoordinate(
        _ coordinate: CLLocationCoordinate2D,
        bearingDegrees: Double,
        meters: CLLocationDistance
    ) -> CLLocationCoordinate2D {
        let earthRadius = 6_371_000.0
        let bearing = bearingDegrees * .pi / 180
        let lat1 = coordinate.latitude * .pi / 180
        let lon1 = coordinate.longitude * .pi / 180
        let angularDistance = meters / earthRadius

        let lat2 = asin(
            sin(lat1) * cos(angularDistance)
                + cos(lat1) * sin(angularDistance) * cos(bearing)
        )
        let lon2 = lon1 + atan2(
            sin(bearing) * sin(angularDistance) * cos(lat1),
            cos(angularDistance) - sin(lat1) * sin(lat2)
        )

        return CLLocationCoordinate2D(latitude: lat2 * 180 / .pi, longitude: lon2 * 180 / .pi)
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
