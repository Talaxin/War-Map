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

    var additionalTimeLabel: String {
        if additionalTime < 30 { return "Fastest" }
        return "+\(DistanceFormatting.format(duration: additionalTime))"
    }

    var detailLabel: String {
        let time = DistanceFormatting.format(duration: route.expectedTravelTime)
        let distance = DistanceFormatting.format(distance: route.distance)
        return "\(time) · \(distance)"
    }

    static func == (lhs: RouteOption, rhs: RouteOption) -> Bool {
        lhs.id == rhs.id
    }
}
