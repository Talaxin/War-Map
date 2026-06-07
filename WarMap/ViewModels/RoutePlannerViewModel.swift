import Combine
import CoreLocation
import Foundation
import MapKit
import UIKit

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

    @Published private(set) var route: MKRoute?
    @Published private(set) var routeOptions: [RouteOption] = []
    @Published private(set) var selectedRouteOptionID: String?
    @Published private(set) var isCalculatingRoute = false
    @Published private(set) var isNavigating = false
    @Published private(set) var followUserOnMap = true
    @Published private(set) var mapTrackingMode: MapTrackingMode = .follow
    @Published private(set) var guidance = NavigationGuidanceState()
    @Published var isSearchPanelExpanded = true
    @Published private(set) var northResetRevision = 0
    @Published private(set) var userCenterRevision = 0

    let locationManager = LocationManager()
    let settings: AppSettings

    private let searchService = AddressSearchService()
    private let directionsService = RouteDirectionsService()
    private let guidanceEngine = NavigationGuidanceEngine()
    private let voiceGuidance: VoiceGuidanceService
    private var routeCalculationTask: Task<Void, Never>?
    private var settingsCancellable: AnyCancellable?
    private var didCenterOnLaunch = false

    var searchCompletions: [MKLocalSearchCompletion] {
        searchService.completions
    }

    var hasRoute: Bool { route != nil }

    var displayedRouteOptions: [RouteOption] {
        if !routeOptions.isEmpty { return routeOptions }
        guard let route else { return [] }
        let newMeters = locationManager.estimateNewDistanceMeters(along: route.polyline)
        return [
            RouteOption(
                id: RouteOption.fingerprint(route),
                route: route,
                additionalTime: 0,
                newRoadMeters: newMeters
            ),
        ]
    }

    var routeUIColor: UIColor { settings.routeColor.uiColor }

    var trackedUIColor: UIColor { settings.trackedColor.uiColor }

    var trackedPolyline: MKPolyline? { locationManager.trackedPolyline }

    var centerButtonSymbolName: String {
        guard followUserOnMap else { return "location.fill" }
        return mapTrackingMode == .followWithHeading ? "location.north.line.fill" : "location.fill"
    }

    var centerButtonAccessibilityLabel: String {
        guard followUserOnMap else { return "Center on your location" }
        return mapTrackingMode == .followWithHeading
            ? "Follow heading"
            : "Center on your location, north up"
    }

    var startDisplayText: String {
        if startUsesCurrentLocation {
            return locationManager.currentAddressLabel
        }
        return startQuery
    }

    var collapsedSummary: String {
        let start = startDisplayText
        let dest = destinationQuery.isEmpty ? "Add destination" : destinationQuery
        return "\(start) → \(dest)"
    }

    var mapRegion: MKCoordinateRegion {
        if isNavigating, let current = locationManager.currentLocation?.coordinate {
            return MKCoordinateRegion(
                center: current,
                latitudinalMeters: 1_500,
                longitudinalMeters: 1_500
            )
        }
        if let route, !isNavigating {
            return MKCoordinateRegion(route.polyline.boundingMapRect)
        }
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

    init(settings: AppSettings) {
        self.settings = settings
        self.voiceGuidance = VoiceGuidanceService(settings: settings)
        locationManager.requestAccessIfNeeded()
        refreshStartFromCurrentLocation()

        settingsCancellable = settings.objectWillChange
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.scheduleRouteCalculation()
            }
    }

    func onAppear() {
        locationManager.requestAccessIfNeeded()
        locationManager.suspendTravelTracking()
        refreshStartFromCurrentLocation()
        centerOnUserAtLaunch()
        syncMapTrackingHardware()
    }

    func handleAuthorizationChange() {
        centerOnUserAtLaunch()
    }

    func focus(_ field: RouteField) {
        isSearchPanelExpanded = true
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

    func expandSearchPanel() {
        isSearchPanelExpanded = true
    }

    func collapseSearchPanel() {
        isSearchPanelExpanded = false
        blurSearch()
        KeyboardDismiss.resign()
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
        let hint = locationManager.currentAddressLabel
        searchService.updateQuery(query, near: coordinate, localityHint: hint)
    }

    func useCurrentLocationForStart() {
        startUsesCurrentLocation = true
        startQuery = ""
        searchService.clear()
        focusedField = nil
        refreshStartFromCurrentLocation()
        scheduleRouteCalculation()
    }

    func refreshStartFromCurrentLocation() {
        guard startUsesCurrentLocation, let location = locationManager.currentLocation else { return }
        startPlace = MapPlace(
            title: locationManager.currentAddressLabel,
            subtitle: nil,
            coordinate: location.coordinate
        )
    }

    func selectCompletion(_ completion: MKLocalSearchCompletion, field: RouteField) async {
        searchService.clear()
        focusedField = nil
        KeyboardDismiss.resign()

        switch field {
        case .start:
            startUsesCurrentLocation = false
            startQuery = completion.title
        case .destination:
            destinationQuery = completion.title
        }

        isResolvingSearch = true
        searchError = nil
        defer { isResolvingSearch = false }

        do {
            let place = try await searchService.resolve(completion)
            switch field {
            case .start:
                startPlace = place
                startQuery = place.title
            case .destination:
                destinationPlace = place
                destinationQuery = place.title
            }
            scheduleRouteCalculation()
        } catch {
            searchError = error.localizedDescription
            switch field {
            case .start:
                startPlace = nil
            case .destination:
                destinationPlace = nil
            }
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
        } else {
            scheduleRouteCalculation()
        }
    }

    func handleStartQueryChange() {
        if startUsesCurrentLocation { startUsesCurrentLocation = false }
        if startQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            startPlace = nil
            scheduleRouteCalculation()
        }
        updateSearchQuery()
    }

    func handleDestinationQueryChange() {
        if destinationQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            destinationPlace = nil
            clearRoute()
        }
        updateSearchQuery()
    }

    func clearStart() {
        startUsesCurrentLocation = false
        startQuery = ""
        startPlace = nil
        searchService.clear()
        if focusedField == .start {
            focusedField = nil
        }
        scheduleRouteCalculation()
    }

    func clearDestination() {
        destinationQuery = ""
        destinationPlace = nil
        searchService.clear()
        if focusedField == .destination {
            focusedField = nil
        }
        clearRoute()
    }

    var canClearStart: Bool {
        startUsesCurrentLocation || startPlace != nil || !startQuery.isEmpty
    }

    var canClearDestination: Bool {
        destinationPlace != nil || !destinationQuery.isEmpty
    }

    func handleLocationUpdate() {
        centerOnUserAtLaunch()
        if startUsesCurrentLocation {
            refreshStartFromCurrentLocation()
        }
        guard isNavigating, let location = locationManager.currentLocation else { return }
        if guidanceEngine.update(userLocation: location) {
            announceGuidanceIfNeeded()
        }
        guidance = guidanceEngine.state
        if guidance.arrived {
            stopNavigation()
        }
    }

    func startNavigation() {
        guard route != nil else { return }
        isNavigating = true
        followUserOnMap = true
        mapTrackingMode = .follow
        syncMapTrackingHardware()
        collapseSearchPanel()
        locationManager.startNavigationUpdates()
        if let location = locationManager.currentLocation {
            _ = guidanceEngine.update(userLocation: location)
            guidance = guidanceEngine.state
            announceGuidanceIfNeeded()
        }
    }

    func stopNavigation() {
        isNavigating = false
        locationManager.stopNavigationUpdates()
        voiceGuidance.stop()
        if locationManager.isAuthorized {
            followUserOnMap = true
            mapTrackingMode = .follow
        }
        syncMapTrackingHardware()
    }

    func recenterOnUser() {
        if !followUserOnMap {
            followUserOnMap = true
            mapTrackingMode = .follow
        } else {
            mapTrackingMode = mapTrackingMode == .follow ? .followWithHeading : .follow
        }
        syncMapTrackingHardware()
    }

    func userDidInteractWithMap() {
        followUserOnMap = false
        syncMapTrackingHardware()
    }

    func resetMapNorth() {
        northResetRevision += 1
    }

    private func centerOnUserAtLaunch() {
        guard !didCenterOnLaunch else { return }
        guard locationManager.isAuthorized, locationManager.currentLocation != nil else { return }
        guard !isNavigating, route == nil else { return }

        didCenterOnLaunch = true
        followUserOnMap = true
        mapTrackingMode = .follow
        syncMapTrackingHardware()
        userCenterRevision += 1
    }

    func setDestination(from saved: SavedLocation) {
        let place = MapPlace(
            title: saved.name,
            subtitle: saved.detail,
            coordinate: saved.mapPlace.coordinate
        )
        destinationPlace = place
        destinationQuery = saved.name
        searchService.clear()
        focusedField = nil
        isSearchPanelExpanded = true
        scheduleRouteCalculation()
    }

    func saveCurrentDestination(as name: String) {
        guard let destinationPlace else { return }
        settings.savedLocations.add(name: name, place: destinationPlace)
    }

    var currentDestinationForSaving: MapPlace? { destinationPlace }

    func selectRouteOption(_ option: RouteOption) {
        guard !isNavigating else { return }
        applyRoute(option.route, selectedID: option.id)
    }

    private func syncMapTrackingHardware() {
        locationManager.setFollowHeadingEnabled(
            followUserOnMap && mapTrackingMode == .followWithHeading
        )
    }

    func scheduleRouteCalculation() {
        routeCalculationTask?.cancel()
        guard let startPlace, let destinationPlace else {
            clearRoute()
            return
        }
        routeCalculationTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await calculateRoute(from: startPlace, to: destinationPlace)
        }
    }

    private func calculateRoute(from start: MapPlace, to destination: MapPlace) async {
        if isNavigating { stopNavigation() }
        isCalculatingRoute = true
        searchError = nil
        defer { isCalculatingRoute = false }

        do {
            let routes = try await directionsService.calculateRoutes(
                from: start,
                to: destination,
                preferences: settings.routePreferences,
                discoverNewRoadAlternates: true
            )
            let options = buildRouteOptions(from: routes)
            routeOptions = options

            let previousID = selectedRouteOptionID
            let defaultOption = preferredDefaultOption(from: options, previousID: previousID)
                ?? options.first
            if let defaultOption {
                applyRoute(defaultOption.route, selectedID: defaultOption.id)
            } else if let fallback = routes.min(by: { $0.expectedTravelTime < $1.expectedTravelTime }) {
                applyRoute(fallback, selectedID: RouteOption.fingerprint(fallback))
            } else {
                clearRoute()
            }
        } catch {
            clearRoute()
            if !Task.isCancelled {
                searchError = error.localizedDescription
            }
        }
    }

    private func clearRoute() {
        route = nil
        routeOptions = []
        selectedRouteOptionID = nil
        locationManager.setSnapRoute(nil)
        guidanceEngine.reset()
        guidance = guidanceEngine.state
    }

    private func applyRoute(_ newRoute: MKRoute, selectedID: String) {
        route = newRoute
        selectedRouteOptionID = selectedID
        locationManager.setSnapRoute(newRoute)
        guidanceEngine.load(route: newRoute)
        guidance = guidanceEngine.state
    }

    private func buildRouteOptions(from candidates: [MKRoute]) -> [RouteOption] {
        guard let referenceRoute = candidates.min(by: { $0.expectedTravelTime < $1.expectedTravelTime }) else {
            return []
        }

        struct Scored {
            let route: MKRoute
            let newMeters: CLLocationDistance

            var id: String { RouteOption.fingerprint(route) }
        }

        var byID: [String: Scored] = [:]
        for route in candidates {
            let item = Scored(
                route: route,
                newMeters: locationManager.estimateNewDistanceMeters(along: route.polyline)
            )
            if let existing = byID[item.id] {
                if item.route.expectedTravelTime < existing.route.expectedTravelTime {
                    byID[item.id] = item
                }
            } else {
                byID[item.id] = item
            }
        }

        let sortedByTime = byID.values.sorted {
            $0.route.expectedTravelTime < $1.route.expectedTravelTime
        }

        let percent = max(0, min(100, settings.newRoadPercent))
        let slider = Double(percent) / 100.0
        let minNewRequired = slider * referenceRoute.distance

        let pool: [Scored]
        if percent == 0 {
            pool = sortedByTime
        } else {
            let qualifying = sortedByTime.filter { $0.newMeters >= minNewRequired - 1 }
            if qualifying.isEmpty {
                pool = sortedByTime
            } else {
                pool = qualifying
            }
        }

        guard let fastest = pool.first else { return [] }
        let baselineTime = fastest.route.expectedTravelTime

        var picks: [Scored] = []
        var seenIDs: Set<String> = []

        func appendUnique(_ item: Scored) {
            guard !seenIDs.contains(item.id) else { return }
            seenIDs.insert(item.id)
            picks.append(item)
        }

        appendUnique(fastest)

        if percent == 0 {
            for item in pool where picks.count < 3 {
                appendUnique(item)
            }
        } else {
            let targetNew = minNewRequired
            let byNewRoadFit = pool.filter { $0.id != fastest.id }.sorted {
                let lhsFit = abs($0.newMeters - targetNew)
                let rhsFit = abs($1.newMeters - targetNew)
                if abs(lhsFit - rhsFit) > 1 { return lhsFit < rhsFit }
                return $0.route.expectedTravelTime < $1.route.expectedTravelTime
            }
            for item in byNewRoadFit where picks.count < 3 {
                appendUnique(item)
            }
            for item in pool.sorted(by: { $0.route.expectedTravelTime < $1.route.expectedTravelTime }) where picks.count < 3 {
                appendUnique(item)
            }
        }

        return picks
            .sorted { $0.route.expectedTravelTime < $1.route.expectedTravelTime }
            .prefix(3)
            .map {
                RouteOption(
                    id: $0.id,
                    route: $0.route,
                    additionalTime: max(0, $0.route.expectedTravelTime - baselineTime),
                    newRoadMeters: $0.newMeters
                )
            }
    }

    private func preferredDefaultOption(from options: [RouteOption], previousID: String?) -> RouteOption? {
        guard !options.isEmpty else { return nil }

        if let previousID, let kept = options.first(where: { $0.id == previousID }) {
            return kept
        }

        let percent = max(0, min(100, settings.newRoadPercent))
        if percent >= 100 {
            return options.max(by: { $0.newRoadMeters < $1.newRoadMeters })
        }

        return options.min(by: { $0.route.expectedTravelTime < $1.route.expectedTravelTime })
    }

    private func announceGuidanceIfNeeded() {
        guard let text = guidanceEngine.shouldAnnounceStep() else { return }
        if guidance.arrived {
            guidanceEngine.markArrivalAnnounced()
        }
        voiceGuidance.speak(text)
    }
}
