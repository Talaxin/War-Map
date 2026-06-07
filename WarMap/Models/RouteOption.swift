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
    func shortTitle(
        relativeTo baseline: MKRoute,
        preferences: DistanceUnitPreferences,
        isBaseline: Bool
    ) -> String {
        if isBaseline {
            return "Fastest"
        }

        let timeDelta = route.expectedTravelTime - baseline.expectedTravelTime
        let timePart = DistanceFormatting.formatAdditionalDuration(timeDelta)
        let distanceDelta = route.distance - baseline.distance
        let distancePart = DistanceFormatting.formatAdditionalDistance(
            max(0, distanceDelta),
            preferences: preferences
        )
        return "+\(timePart) +\(distancePart)"
    }

    func detailLabel(preferences: DistanceUnitPreferences) -> String {
        let time = DistanceFormatting.format(duration: route.expectedTravelTime)
        let distance = DistanceFormatting.format(distance: route.distance, preferences: preferences)
        return "\(time) · \(distance)"
    }

    static func == (lhs: RouteOption, rhs: RouteOption) -> Bool {
        lhs.id == rhs.id
    }
}
