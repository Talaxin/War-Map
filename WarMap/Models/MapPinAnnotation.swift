import MapKit

final class MapPinAnnotation: MKPointAnnotation {
    enum Role: String {
        case start
        case destination
    }

    let role: Role

    init(role: Role, placeName: String, coordinate: CLLocationCoordinate2D) {
        self.role = role
        super.init()
        self.title = placeName
        self.coordinate = coordinate
    }
}
