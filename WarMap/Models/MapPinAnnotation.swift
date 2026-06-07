import CoreLocation
import MapKit

final class SnappedUserLocationAnnotation: NSObject, MKAnnotation {
    dynamic var coordinate: CLLocationCoordinate2D
    var course: CLLocationDirection

    init(coordinate: CLLocationCoordinate2D, course: CLLocationDirection = -1) {
        self.coordinate = coordinate
        self.course = course
    }
}

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
