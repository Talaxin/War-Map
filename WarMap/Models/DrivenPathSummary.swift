import CoreLocation
import Foundation

struct DrivenPathSummary: Identifiable, Equatable {
    let id: Int
    let distanceMeters: CLLocationDistance
    let pointCount: Int

    var title: String {
        "Route \(id + 1)"
    }

    var detail: String {
        "\(DistanceFormatting.format(distance: distanceMeters)) · \(pointCount) points"
    }
}
