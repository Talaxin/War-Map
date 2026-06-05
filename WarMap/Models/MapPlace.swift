import CoreLocation
import MapKit

struct MapPlace: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let subtitle: String?
    let coordinate: CLLocationCoordinate2D

    static func == (lhs: MapPlace, rhs: MapPlace) -> Bool {
        lhs.title == rhs.title
            && lhs.subtitle == rhs.subtitle
            && lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
    }
}
