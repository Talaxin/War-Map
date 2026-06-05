import Combine
import CoreLocation
import Foundation
import MapKit

enum RouteField: Hashable {
    case start
    case destination
}

@MainActor
final class RoutePlannerViewModel: ObservableObject {
    @Published var startQuery = ""
    @Published var destinationQuery = ""
    @Published var focusedField: RouteField?
    @Published private(set) var startPlace: MapPlace?
    @Published private(set) var destinationPlace: MapPlace?
    @Published private(set) var startUsesCurrentLocation = true
    @Published private(set) var isResolvingSearch = false
    @Published var searchError: String?

    let locationManager = LocationManager()
    private let searchService = AddressSearchService()

    var searchCompletions: [MKLocalSearchCompletion] {
        searchService.completions
    }

    var startDisplayText: String {
        if startUsesCurrentLocation {
            return locationManager.currentAddressLabel
        }
        return startQuery
    }

    var mapRegion: MKCoordinateRegion {
        let points = [startPlace, destinationPlace].compactMap(\.?.coordinate)
        guard !points.isEmpty else {
            if let current = locationManager.currentLocation?.coordinate {
                return MKCoordinateRegion(
                    center: current,
                    latitudinalMeters: 12_000,
                    longitudinalMeters: 12_000
                )
            }
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090),
                latitudinalMeters: 25_000,
                longitudinalMeters: 25_000
            )
        }
        if points.count == 1, let center = points.first {
            return MKCoordinateRegion(
                center: center,
                latitudinalMeters: 8_000,
                longitudinalMeters: 8_000
            )
        }
        var rect = MKMapRect.null
        for coordinate in points {
            let point = MKMapPoint(coordinate)
            let pointRect = MKMapRect(x: point.x, y: point.y, width: 0.1, height: 0.1)
            rect = rect.union(pointRect)
        }
        let padding = 1.35
        rect = rect.insetBy(
            dx: -rect.size.width * (padding - 1) / 2,
            dy: -rect.size.height * (padding - 1) / 2
        )
        return MKCoordinateRegion(rect)
    }

    init() {
        locationManager.requestAccessIfNeeded()
        refreshStartFromCurrentLocation()
    }

    func onAppear() {
        locationManager.requestAccessIfNeeded()
        refreshStartFromCurrentLocation()
    }

    func focus(_ field: RouteField) {
        focusedField = field
        if field == .start, startUsesCurrentLocation {
            startQuery = locationManager.currentAddressLabel
            startUsesCurrentLocation = false
        }
        updateSearchQuery()
    }

    func blurSearch() {
        focusedField = nil
        searchService.clear()
    }

    func updateSearchQuery() {
        guard let field = focusedField else {
            searchService.clear()
            return
        }
        let query: String
        switch field {
        case .start:
            query = startQuery
        case .destination:
            query = destinationQuery
        }
        let coordinate = locationManager.currentLocation?.coordinate
        searchService.updateQuery(query, near: coordinate)
    }

    func useCurrentLocationForStart() {
        startUsesCurrentLocation = true
        startQuery = ""
        searchService.clear()
        focusedField = nil
        refreshStartFromCurrentLocation()
    }

    func refreshStartFromCurrentLocation() {
        guard startUsesCurrentLocation, let location = locationManager.currentLocation else { return }
        startPlace = MapPlace(
            title: locationManager.currentAddressLabel,
            subtitle: nil,
            coordinate: location.coordinate
        )
    }

    func selectCompletion(_ completion: MKLocalSearchCompletion) async {
        isResolvingSearch = true
        searchError = nil
        defer { isResolvingSearch = false }

        do {
            let place = try await searchService.resolve(completion)
            switch focusedField {
            case .start:
                startPlace = place
                startUsesCurrentLocation = false
                startQuery = place.title
            case .destination:
                destinationPlace = place
                destinationQuery = place.title
            case .none:
                break
            }
            searchService.clear()
            focusedField = nil
        } catch {
            searchError = error.localizedDescription
        }
    }

    func swapEndpoints() {
        let oldStartPlace = startPlace
        let oldDestPlace = destinationPlace
        let oldStartQuery = startQuery
        let oldDestQuery = destinationQuery
        let oldStartUsesLocation = startUsesCurrentLocation

        startPlace = oldDestPlace
        destinationPlace = oldStartPlace
        startQuery = oldDestQuery
        destinationQuery = oldStartQuery
        startUsesCurrentLocation = false

        if oldDestPlace == nil && oldStartUsesLocation {
            useCurrentLocationForStart()
        }
    }

    func handleStartQueryChange() {
        if startUsesCurrentLocation { startUsesCurrentLocation = false }
        updateSearchQuery()
    }

    func handleDestinationQueryChange() {
        updateSearchQuery()
    }
}
