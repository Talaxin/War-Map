import Combine
import CoreLocation
import Foundation
import MapKit

@MainActor
final class LocationManager: NSObject, ObservableObject {
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var currentLocation: CLLocation?
    @Published private(set) var currentAddressLabel: String = "My Location"

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var isNavigationMode = false
    private let travelHistory = TravelHistoryStore()
    private var lastTrackedLocation: CLLocation?
    @Published private(set) var trackedPathRevision = 0

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
    }

    var isAuthorized: Bool {
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return true
        default:
            return false
        }
    }

    func requestAccessIfNeeded() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            break
        }
    }

    func startNavigationUpdates() {
        isNavigationMode = true
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = 8
        manager.startUpdatingLocation()
        updateHeadingUpdates()
    }

    func stopNavigationUpdates() {
        isNavigationMode = false
        updateHeadingUpdates()
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.startUpdatingLocation()
    }

    /// Enables compass heading for map follow-with-heading mode (outside navigation).
    func setFollowHeadingEnabled(_ enabled: Bool) {
        wantsHeadingForMap = enabled
        updateHeadingUpdates()
    }

    private var wantsHeadingForMap = false

    private func updateHeadingUpdates() {
        let needsHeading = (isNavigationMode || wantsHeadingForMap) && CLLocationManager.headingAvailable()
        if needsHeading {
            manager.startUpdatingHeading()
        } else {
            manager.stopUpdatingHeading()
        }
    }

    private func reverseGeocode(_ location: CLLocation) {
        guard !isNavigationMode else { return }
        geocoder.cancelGeocode()
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            guard let self else { return }
            Task { @MainActor in
                if let placemark = placemarks?.first {
                    self.currentAddressLabel = Self.format(placemark) ?? "My Location"
                } else {
                    self.currentAddressLabel = "My Location"
                }
            }
        }
    }

    private static func format(_ placemark: CLPlacemark) -> String? {
        if let thoroughfare = placemark.thoroughfare, let locality = placemark.locality {
            return "\(thoroughfare), \(locality)"
        }
        return placemark.name ?? placemark.locality ?? placemark.administrativeArea
    }
}

extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
            if isAuthorized {
                manager.startUpdatingLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            currentLocation = location
            reverseGeocode(location)
            trackTravelIfPossible(location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // GPS can be unavailable in Simulator.
    }
}

@MainActor
extension LocationManager {
    func isVisited(_ coordinate: CLLocationCoordinate2D) -> Bool {
        travelHistory.isVisited(coordinate)
    }

    func estimateNewDistanceMeters(along polyline: MKPolyline) -> CLLocationDistance {
        travelHistory.estimateNewDistanceMeters(along: polyline)
    }

    var trackedPolyline: MKPolyline? {
        travelHistory.trackedPolyline
    }

    private func notifyTrackedPathChanged() {
        trackedPathRevision += 1
    }

    private func trackTravelIfPossible(_ location: CLLocation) {
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 35 else { return }

        if let lastTrackedLocation {
            let delta = location.distance(from: lastTrackedLocation)
            guard delta >= 12 else { return }

            let elapsed = max(location.timestamp.timeIntervalSince(lastTrackedLocation.timestamp), 0.5)
            let impliedSpeed = delta / elapsed
            let speed = location.speed >= 0 ? location.speed : impliedSpeed
            // Record only when actually moving along roads (not stationary GPS drift).
            guard speed >= 2.5 else { return }

            travelHistory.recordTravel(from: lastTrackedLocation.coordinate, to: location.coordinate)
            self.lastTrackedLocation = location
            notifyTrackedPathChanged()
        } else if location.speed >= 2.5 {
            travelHistory.recordVisit(at: location.coordinate)
            lastTrackedLocation = location
            notifyTrackedPathChanged()
        }
    }
}

/// Very lightweight, persistent "visited" store for wardriving-style routing.
/// We intentionally track where the user *actually drove* (GPS trace), not the planned route.
@MainActor
final class TravelHistoryStore {
    private let cellSizeMeters: Double = 30
    private let saveDebounceSeconds: TimeInterval = 3
    private var visited = Set<Int64>()
    private var pathPoints: [CLLocationCoordinate2D] = []
    private var saveTask: Task<Void, Never>?

    private var cellsFileURL: URL {
        appSupportFile(named: "visited-cells.plist")
    }

    private var pathFileURL: URL {
        appSupportFile(named: "driven-path.plist")
    }

    private func appSupportFile(named: String) -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = dir.appendingPathComponent("WarMap", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent(named)
    }

    init() {
        load()
    }

    var trackedPolyline: MKPolyline? {
        guard pathPoints.count >= 2 else { return nil }
        var coords = pathPoints
        let polyline = MKPolyline(coordinates: &coords, count: coords.count)
        polyline.title = "tracked"
        return polyline
    }

    func isVisited(_ coordinate: CLLocationCoordinate2D) -> Bool {
        visited.contains(cellKey(for: coordinate))
    }

    func recordVisit(at coordinate: CLLocationCoordinate2D) {
        visited.insert(cellKey(for: coordinate))
        appendPathPoint(coordinate)
        scheduleSave()
    }

    func recordTravel(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) {
        // Sample along the driven segment so we don't miss cells at higher speeds.
        let a = MKMapPoint(from)
        let b = MKMapPoint(to)
        let meters = a.distance(to: b)
        guard meters > 0 else { return }

        let step = max(cellSizeMeters * 0.75, 10)
        let steps = max(Int(ceil(meters / step)), 1)
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let x = a.x + (b.x - a.x) * t
            let y = a.y + (b.y - a.y) * t
            visited.insert(cellKey(forMapPointX: x, y: y))
        }
        appendPathPoint(to)
        scheduleSave()
    }

    private func appendPathPoint(_ coordinate: CLLocationCoordinate2D) {
        if let last = pathPoints.last {
            let lastLocation = CLLocation(latitude: last.latitude, longitude: last.longitude)
            let nextLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            guard lastLocation.distance(from: nextLocation) >= 8 else { return }
        }
        pathPoints.append(coordinate)
    }

    func estimateNewDistanceMeters(along polyline: MKPolyline) -> CLLocationDistance {
        guard polyline.pointCount >= 2 else { return 0 }
        let pts = polyline.points()
        var newDistance: CLLocationDistance = 0

        for i in 1..<polyline.pointCount {
            let start = pts[i - 1].coordinate
            let end = pts[i].coordinate
            let segmentMeters = MKMapPoint(start).distance(to: MKMapPoint(end))
            guard segmentMeters > 0 else { continue }

            let samples = max(Int(ceil(segmentMeters / (cellSizeMeters * 0.5))), 1)
            var unvisitedSamples = 0
            for s in 0...samples {
                let t = Double(s) / Double(samples)
                let point = CLLocationCoordinate2D(
                    latitude: start.latitude + (end.latitude - start.latitude) * t,
                    longitude: start.longitude + (end.longitude - start.longitude) * t
                )
                if !isVisited(point) {
                    unvisitedSamples += 1
                }
            }
            newDistance += segmentMeters * Double(unvisitedSamples) / Double(samples + 1)
        }
        return newDistance
    }

    private func cellKey(for coordinate: CLLocationCoordinate2D) -> Int64 {
        let p = MKMapPoint(coordinate)
        return cellKey(forMapPointX: p.x, y: p.y)
    }

    private func cellKey(forMapPointX x: Double, y: Double) -> Int64 {
        let ix = Int32(floor(x / cellSizeMeters))
        let iy = Int32(floor(y / cellSizeMeters))
        return (Int64(ix) << 32) | (Int64(UInt32(bitPattern: iy)))
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let cells = visited
        let path = pathPoints
        let cellsURL = cellsFileURL
        let pathURL = pathFileURL
        saveTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(saveDebounceSeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            if let data = try? PropertyListEncoder().encode(Array(cells)) {
                try? data.write(to: cellsURL, options: [.atomic])
            }
            let encodedPath = path.map { [$0.latitude, $0.longitude] }
            if let data = try? PropertyListEncoder().encode(encodedPath) {
                try? data.write(to: pathURL, options: [.atomic])
            }
        }
    }

    private func load() {
        if let data = try? Data(contentsOf: cellsFileURL),
           let decoded = try? PropertyListDecoder().decode([Int64].self, from: data) {
            visited = Set(decoded)
        }
        if let data = try? Data(contentsOf: pathFileURL),
           let decoded = try? PropertyListDecoder().decode([[Double]].self, from: data) {
            pathPoints = decoded.compactMap { pair in
                guard pair.count == 2 else { return nil }
                return CLLocationCoordinate2D(latitude: pair[0], longitude: pair[1])
            }
        }
    }
}
