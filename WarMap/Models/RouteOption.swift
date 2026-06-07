import CoreLocation
import Foundation
import MapKit

struct RouteOption: Identifiable, Equatable {
    let id: String
    let route: MKRoute
    let additionalTime: TimeInterval
    let newRoadMeters: CLLocationDistance

    static func fingerprint(_ route: MKRoute) -> String {
        "\(route.distance)-\(route.expectedTravelTime)-\(route.polyline.pointCount)"
    }

    /// Short label for the route picker card title.
    func shortTitle(relativeTo baseline: MKRoute, preferences: DistanceUnitPreferences) -> String {
        let timeDelta = route.expectedTravelTime - baseline.expectedTravelTime
        if timeDelta < 1 {
            return "Fastest"
        }
        let timePart = DistanceFormatting.format(duration: timeDelta)
        let distanceDelta = max(0, route.distance - baseline.distance)
        let distancePart = DistanceFormatting.format(distance: distanceDelta, preferences: preferences)
        return "+\(timePart) · +\(distancePart)"
    }

    func detailLabel(preferences: DistanceUnitPreferences) -> String {
        let time = DistanceFormatting.format(duration: route.expectedTravelTime)
        let distance = DistanceFormatting.format(distance: route.distance, preferences: preferences)
        let newRoad = DistanceFormatting.format(distance: newRoadMeters, preferences: preferences)
        return "\(time) · \(distance) · \(newRoad) new"
    }

    static func == (lhs: RouteOption, rhs: RouteOption) -> Bool {
        lhs.id == rhs.id
    }
}
