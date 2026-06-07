import Combine
import CoreLocation
import Foundation
import MapKit
import UIKit

@MainActor
final class LocationManager: NSObject, ObservableObject {
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var currentLocation: CLLocation?
    @Published private(set) var currentAddressLabel: String = "My Location"

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var isNavigationMode = false
    private var snapRoutePolyline: MKPolyline?
    private let travelHistory = TravelHistoryStore()
    private var lastRawLocation: CLLocation?
    private var lastTrackedLocation: CLLocation?
    @Published private(set) var trackedPathRevision = 0
    @Published var highlightedSegmentIndex: Int?

    private let maxTrackingGapSeconds: TimeInterval = 90
    private let maxTrackingGapMeters: CLLocationDistance = 200

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
        registerAppLifecycleObservers()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
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

    func setSnapRoute(_ route: MKRoute?) {
        snapRoutePolyline = route?.polyline
        if let lastRawLocation {
            applySnappedLocation(from: lastRawLocation, forceRepublish: true)
        }
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
            applySnappedLocation(from: location)
            reverseGeocode(location)
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

    var trackedPolylines: [MKPolyline] {
        travelHistory.trackedPolylines
    }

    var drivenPathSummaries: [DrivenPathSummary] {
        travelHistory.segmentSummaries()
    }

    func setHighlightedSegment(_ index: Int?) {
        highlightedSegmentIndex = index
    }

    func deleteDrivenSegment(at index: Int) {
        travelHistory.removeSegment(at: index)
        if highlightedSegmentIndex == index {
            highlightedSegmentIndex = nil
        } else if let highlightedSegmentIndex, highlightedSegmentIndex > index {
            self.highlightedSegmentIndex = highlightedSegmentIndex - 1
        }
        notifyTrackedPathChanged()
    }

    func suspendTravelTracking() {
        lastTrackedLocation = nil
    }

    private func applySnappedLocation(from raw: CLLocation, forceRepublish: Bool = false) {
        lastRawLocation = raw
        let snapped = roadSnappedLocation(from: raw)
        if forceRepublish || !coordinatesEqual(currentLocation?.coordinate, snapped.coordinate) {
            currentLocation = snapped
        }
        trackTravelIfPossible(snapped)
    }

    private func coordinatesEqual(
        _ lhs: CLLocationCoordinate2D?,
        _ rhs: CLLocationCoordinate2D
    ) -> Bool {
        guard let lhs else { return false }
        return lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }

    private func roadSnappedLocation(from raw: CLLocation) -> CLLocation {
        let maxDistance = isNavigationMode
            ? RoadSnapper.navigationMaxDistance
            : RoadSnapper.trackingMaxDistance

        guard let match = RoadSnapper.snap(
            raw.coordinate,
            routePolyline: snapRoutePolyline,
            trackedPolylines: trackedPolylines,
            preferRoute: isNavigationMode,
            maxDistance: maxDistance
        ) else {
            return raw
        }

        var course = raw.course
        if course < 0, let bearing = match.segmentBearing {
            course = bearing
        }

        return CLLocation(
            coordinate: match.coordinate,
            altitude: raw.altitude,
            horizontalAccuracy: raw.horizontalAccuracy,
            verticalAccuracy: raw.verticalAccuracy,
            course: course,
            speed: raw.speed,
            timestamp: raw.timestamp
        )
    }

    private func registerAppLifecycleObservers() {
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(handleAppWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleAppDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }

    @objc private func handleAppWillResignActive() {
        suspendTravelTracking()
    }

    @objc private func handleAppDidEnterBackground() {
        suspendTravelTracking()
    }

    private func notifyTrackedPathChanged() {
        trackedPathRevision += 1
    }

    private func hasTrackingGap(since previous: CLLocation, next: CLLocation) -> Bool {
        let elapsed = next.timestamp.timeIntervalSince(previous.timestamp)
        if elapsed > maxTrackingGapSeconds { return true }
        if previous.distance(from: next) > maxTrackingGapMeters { return true }
        if let lastPathPoint = travelHistory.lastPathPoint {
            let gapFromSavedPath = CLLocation(latitude: lastPathPoint.latitude, longitude: lastPathPoint.longitude)
                .distance(from: next)
            if gapFromSavedPath > maxTrackingGapMeters { return true }
        }
        return false
    }

    private func trackTravelIfPossible(_ location: CLLocation) {
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 35 else { return }

        if let lastTrackedLocation {
            if hasTrackingGap(since: lastTrackedLocation, next: location) {
                self.lastTrackedLocation = nil
            }
        }

        if let lastTrackedLocation {
            let delta = location.distance(from: lastTrackedLocation)
            guard delta >= 12 else { return }

            let elapsed = max(location.timestamp.timeIntervalSince(lastTrackedLocation.timestamp), 0.5)
            let impliedSpeed = delta / elapsed
            let speed = location.speed >= 0 ? location.speed : impliedSpeed
            guard speed >= 2.5 else { return }

            travelHistory.recordTravel(from: lastTrackedLocation.coordinate, to: location.coordinate)
            self.lastTrackedLocation = location
            notifyTrackedPathChanged()
        } else if location.speed < 0 || location.speed >= 2.5 {
            travelHistory.beginSegmentIfNeeded(at: location.coordinate)
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
    private var pathSegments: [[CLLocationCoordinate2D]] = []
    private var lastPathPointDate: Date?
    private var saveTask: Task<Void, Never>?

    private let maxPathGapMeters: CLLocationDistance = 200

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

    var lastPathPoint: CLLocationCoordinate2D? {
        pathSegments.last?.last
    }

    var trackedPolyline: MKPolyline? {
        trackedPolylines.first
    }

    var trackedPolylines: [MKPolyline] {
        pathSegments.enumerated().compactMap { index, segment in
            guard segment.count >= 2 else { return nil }
            var coords = segment
            let polyline = MKPolyline(coordinates: &coords, count: coords.count)
            polyline.title = "tracked-\(index)"
            return polyline
        }
    }

    func segmentSummaries() -> [DrivenPathSummary] {
        pathSegments.enumerated().compactMap { index, segment in
            guard segment.count >= 2 else { return nil }
            var distance: CLLocationDistance = 0
            for i in 1..<segment.count {
                let start = CLLocation(latitude: segment[i - 1].latitude, longitude: segment[i - 1].longitude)
                let end = CLLocation(latitude: segment[i].latitude, longitude: segment[i].longitude)
                distance += start.distance(from: end)
            }
            return DrivenPathSummary(id: index, distanceMeters: distance, pointCount: segment.count)
        }
    }

    func removeSegment(at index: Int) {
        guard pathSegments.indices.contains(index) else { return }
        pathSegments.remove(at: index)
        rebuildVisitedCellsFromPaths()
        saveTask?.cancel()
        let cells = visited
        let segments = pathSegments
        let cellsURL = cellsFileURL
        let pathURL = pathFileURL
        saveTask = Task {
            if let data = try? PropertyListEncoder().encode(Array(cells)) {
                try? data.write(to: cellsURL, options: [.atomic])
            }
            let encodedSegments = segments.map { segment in
                segment.map { [$0.latitude, $0.longitude] }
            }
            if let data = try? PropertyListEncoder().encode(encodedSegments) {
                try? data.write(to: pathURL, options: [.atomic])
            }
        }
    }

    private func rebuildVisitedCellsFromPaths() {
        visited.removeAll()
        for segment in pathSegments {
            markVisitedCells(along: segment)
        }
    }

    private func markVisitedCells(along segment: [CLLocationCoordinate2D]) {
        guard segment.count >= 2 else {
            if let first = segment.first {
                visited.insert(cellKey(for: first))
            }
            return
        }

        for index in 1..<segment.count {
            let from = segment[index - 1]
            let to = segment[index]
            let a = MKMapPoint(from)
            let b = MKMapPoint(to)
            let meters = a.distance(to: b)
            guard meters > 0 else { continue }

            let step = max(cellSizeMeters * 0.75, 10)
            let steps = max(Int(ceil(meters / step)), 1)
            for i in 0...steps {
                let t = Double(i) / Double(steps)
                let x = a.x + (b.x - a.x) * t
                let y = a.y + (b.y - a.y) * t
                visited.insert(cellKey(forMapPointX: x, y: y))
            }
        }
    }

    func beginSegmentIfNeeded(at coordinate: CLLocationCoordinate2D) {
        if pathSegments.isEmpty {
            pathSegments.append([coordinate])
            lastPathPointDate = Date()
            return
        }

        guard let last = lastPathPoint else {
            pathSegments.append([coordinate])
            lastPathPointDate = Date()
            return
        }

        let gap = CLLocation(latitude: last.latitude, longitude: last.longitude)
            .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
        if gap > maxPathGapMeters {
            pathSegments.append([coordinate])
            lastPathPointDate = Date()
        }
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
        let gap = CLLocation(latitude: from.latitude, longitude: from.longitude)
            .distance(from: CLLocation(latitude: to.latitude, longitude: to.longitude))
        guard gap <= maxPathGapMeters else {
            beginSegmentIfNeeded(at: to)
            recordVisit(at: to)
            return
        }

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
        if pathSegments.isEmpty {
            pathSegments.append([coordinate])
            lastPathPointDate = Date()
            return
        }

        let segmentIndex = pathSegments.count - 1
        if let last = pathSegments[segmentIndex].last {
            let lastLocation = CLLocation(latitude: last.latitude, longitude: last.longitude)
            let nextLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let gap = lastLocation.distance(from: nextLocation)
            if gap > maxPathGapMeters {
                pathSegments.append([coordinate])
                lastPathPointDate = Date()
                return
            }
            guard gap >= 8 else { return }
        }

        pathSegments[segmentIndex].append(coordinate)
        lastPathPointDate = Date()
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
        let segments = pathSegments
        let cellsURL = cellsFileURL
        let pathURL = pathFileURL
        saveTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(saveDebounceSeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            if let data = try? PropertyListEncoder().encode(Array(cells)) {
                try? data.write(to: cellsURL, options: [.atomic])
            }
            let encodedSegments = segments.map { segment in
                segment.map { [$0.latitude, $0.longitude] }
            }
            if let data = try? PropertyListEncoder().encode(encodedSegments) {
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
           let decoded = try? PropertyListDecoder().decode([[[Double]]].self, from: data) {
            pathSegments = decoded.map { segment in
                segment.compactMap { pair in
                    guard pair.count == 2 else { return nil }
                    return CLLocationCoordinate2D(latitude: pair[0], longitude: pair[1])
                }
            }.filter { !$0.isEmpty }
            return
        }

        if let data = try? Data(contentsOf: pathFileURL),
           let decoded = try? PropertyListDecoder().decode([[Double]].self, from: data) {
            let legacyPoints = decoded.compactMap { pair -> CLLocationCoordinate2D? in
                guard pair.count == 2 else { return nil }
                return CLLocationCoordinate2D(latitude: pair[0], longitude: pair[1])
            }
            if !legacyPoints.isEmpty {
                pathSegments = [legacyPoints]
            }
        }
    }
}
