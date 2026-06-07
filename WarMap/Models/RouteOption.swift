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
    func shortTitle(relativeTo baseline: MKRoute) -> String {
        let timeDelta = route.expectedTravelTime - baseline.expectedTravelTime
        if timeDelta < 1 {
            return "Fastest"
        }
        if timeDelta >= 30 {
            return "+\(DistanceFormatting.format(duration: timeDelta))"
        }
        let distanceDelta = route.distance - baseline.distance
        if distanceDelta > 400 {
            return "Longer"
        }
        if distanceDelta < -400 {
            return "Shorter"
        }
        return "Alternate"
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
