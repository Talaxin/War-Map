import CoreLocation
import Foundation

struct SavedLocation: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var placeTitle: String
    var placeSubtitle: String?
    var latitude: Double
    var longitude: Double

    init(
        id: UUID = UUID(),
        name: String,
        place: MapPlace
    ) {
        self.id = id
        self.name = name
        self.placeTitle = place.title
        self.placeSubtitle = place.subtitle
        self.latitude = place.coordinate.latitude
        self.longitude = place.coordinate.longitude
    }

    var mapPlace: MapPlace {
        MapPlace(
            title: placeTitle,
            subtitle: placeSubtitle,
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        )
    }

    var detail: String {
        if let placeSubtitle, !placeSubtitle.isEmpty {
            return placeSubtitle
        }
        return placeTitle
    }
}
