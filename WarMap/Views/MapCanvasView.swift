import MapKit
import SwiftUI
import UIKit

struct MapCanvasView: UIViewRepresentable {
    let region: MKCoordinateRegion
    let route: MKRoute?
    let trackedPolylines: [MKPolyline]
    let start: MapPlace?
    let destination: MapPlace?
    let showsStartPin: Bool
    let isNavigating: Bool
    let followUser: Bool
    let trackingMode: MapTrackingMode
    let routeColor: UIColor
    let trackedColor: UIColor
    let highlightedTrackSegmentIndex: Int?
    let vehicleType: VehicleType
    let trackedPathRevision: Int
    var northResetRevision: Int = 0
    var onUserInteraction: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.isRotateEnabled = true
        mapView.isZoomEnabled = true
        mapView.isScrollEnabled = true
        mapView.showsUserLocation = true
        mapView.showsCompass = false
        mapView.layoutMargins = UIEdgeInsets(top: 12, left: 12, bottom: 140, right: 12)
        mapView.pointOfInterestFilter = .includingAll
        context.coordinator.installGestureObservers(on: mapView)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.parent = self

        if context.coordinator.lastVehicleType != vehicleType {
            context.coordinator.lastVehicleType = vehicleType
            context.coordinator.refreshUserLocationAnnotation(on: mapView)
        }

        let revisionChanged = trackedPathRevision != context.coordinator.lastTrackedPathRevision
        if revisionChanged {
            context.coordinator.lastTrackedPathRevision = trackedPathRevision
        }

        let routeFingerprint = Self.routeFingerprint(for: route)
        let routeChanged = routeFingerprint != context.coordinator.lastRouteFingerprint
        let highlightChanged = highlightedTrackSegmentIndex != context.coordinator.lastHighlightedTrackSegmentIndex

        if revisionChanged
            || routeChanged
            || highlightChanged
            || context.coordinator.needsOverlayRefresh(parent: self)
            || context.coordinator.lastRouteColor != routeColor
            || context.coordinator.lastTrackedColor != trackedColor {
            if revisionChanged
                || highlightChanged
                || context.coordinator.needsOverlayRefresh(parent: self)
                || context.coordinator.lastTrackedColor != trackedColor {
                mapView.removeOverlays(mapView.overlays.filter { ($0 as? MKPolyline)?.title != "route" })
                for trackedPolyline in trackedPolylines {
                    mapView.addOverlay(trackedPolyline, level: .aboveRoads)
                }
                context.coordinator.lastHadTracked = !trackedPolylines.isEmpty
                context.coordinator.lastTrackedColor = trackedColor
                context.coordinator.lastHighlightedTrackSegmentIndex = highlightedTrackSegmentIndex
            }

            if routeChanged
                || revisionChanged
                || context.coordinator.lastRouteColor != routeColor
                || context.coordinator.needsOverlayRefresh(parent: self) {
                mapView.removeOverlays(mapView.overlays.filter { ($0 as? MKPolyline)?.title == "route" })
                if let route {
                    let polyline = route.polyline
                    polyline.title = "route"
                    mapView.addOverlay(polyline, level: .aboveRoads)
                }
                context.coordinator.lastHadRoute = route != nil
                context.coordinator.lastRouteColor = routeColor
                context.coordinator.lastRouteFingerprint = routeFingerprint
            }
        }

        mapView.removeAnnotations(mapView.annotations.filter { !($0 is MKUserLocation) })
        if let start, showsStartPin, !isNavigating {
            let coordinate = Self.routeEndpoint(for: route, atStart: true) ?? start.coordinate
            let annotation = MapPinAnnotation(
                role: .start,
                placeName: start.title,
                coordinate: coordinate
            )
            mapView.addAnnotation(annotation)
        }
        if let destination {
            let coordinate = Self.routeEndpoint(for: route, atStart: false) ?? destination.coordinate
            let annotation = MapPinAnnotation(
                role: .destination,
                placeName: destination.title,
                coordinate: coordinate
            )
            mapView.addAnnotation(annotation)
        }

        if northResetRevision != context.coordinator.lastNorthResetRevision {
            context.coordinator.lastNorthResetRevision = northResetRevision
            let camera = mapView.camera.copy() as! MKMapCamera
            camera.heading = 0
            mapView.setCamera(camera, animated: true)
        }

        let followChanged = followUser != context.coordinator.lastFollowUser
        let trackingModeChanged = trackingMode != context.coordinator.lastTrackingMode

        if followUser {
            let mode: MKUserTrackingMode = trackingMode == .followWithHeading ? .followWithHeading : .follow
            if mapView.userTrackingMode != mode || followChanged || trackingModeChanged {
                context.coordinator.setProgrammaticChange(true)
                mapView.setUserTrackingMode(mode, animated: followChanged || trackingModeChanged)
                context.coordinator.setProgrammaticChange(false)
            }
        } else {
            mapView.isRotateEnabled = true
            if mapView.userTrackingMode != .none {
                context.coordinator.setProgrammaticChange(true)
                mapView.setUserTrackingMode(.none, animated: false)
                context.coordinator.setProgrammaticChange(false)
            }

            if context.coordinator.shouldApplyIdleViewport(
                parent: self,
                followChanged: followChanged,
                routeChanged: routeChanged,
                highlightChanged: highlightChanged
            ) {
                context.coordinator.setProgrammaticChange(true)
                if let index = highlightedTrackSegmentIndex,
                   trackedPolylines.indices.contains(index),
                   !isNavigating {
                    let padding = UIEdgeInsets(top: 120, left: 48, bottom: 200, right: 48)
                    mapView.setVisibleMapRect(
                        trackedPolylines[index].boundingMapRect,
                        edgePadding: padding,
                        animated: true
                    )
                } else if let route, !isNavigating {
                    let padding = UIEdgeInsets(top: 120, left: 48, bottom: 200, right: 48)
                    mapView.setVisibleMapRect(
                        route.polyline.boundingMapRect,
                        edgePadding: padding,
                        animated: followChanged && !routeChanged
                    )
                } else if !isNavigating {
                    mapView.setRegion(region, animated: followChanged && !routeChanged)
                }
                context.coordinator.recordIdleViewport(parent: self)
                context.coordinator.setProgrammaticChange(false)
            }
        }

        context.coordinator.lastFollowUser = followUser
        context.coordinator.lastTrackingMode = trackingMode
    }

    private static func routeFingerprint(for route: MKRoute?) -> String {
        guard let route else { return "none" }
        return RouteOption.fingerprint(route)
    }

    private static func routeEndpoint(for route: MKRoute?, atStart: Bool) -> CLLocationCoordinate2D? {
        guard let route, route.polyline.pointCount > 0 else { return nil }
        let points = route.polyline.points()
        return atStart
            ? points[0].coordinate
            : points[route.polyline.pointCount - 1].coordinate
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapCanvasView
        var lastVehicleType: VehicleType?
        var lastTrackedPathRevision = -1
        var lastHadTracked = false
        var lastHadRoute = false
        var lastRouteFingerprint: String?
        var lastRouteColor: UIColor?
        var lastTrackedColor: UIColor?
        var lastHighlightedTrackSegmentIndex: Int?
        var lastFollowUser = true
        var lastTrackingMode: MapTrackingMode = .follow
        var lastNorthResetRevision = -1
        var idleViewportKey: String?
        private var isProgrammaticRegionChange = false
        private var programmaticChangeDepth = 0
        private weak var observedPanGesture: UIPanGestureRecognizer?
        private weak var observedPinchGesture: UIPinchGestureRecognizer?
        private weak var observedRotationGesture: UIRotationGestureRecognizer?

        init(parent: MapCanvasView) {
            self.parent = parent
            lastVehicleType = parent.vehicleType
            lastFollowUser = parent.followUser
            lastTrackingMode = parent.trackingMode
        }

        func setProgrammaticChange(_ active: Bool) {
            if active {
                programmaticChangeDepth += 1
                isProgrammaticRegionChange = true
            } else {
                programmaticChangeDepth = max(0, programmaticChangeDepth - 1)
                if programmaticChangeDepth == 0 {
                    isProgrammaticRegionChange = false
                }
            }
        }

        func installGestureObservers(on mapView: MKMapView) {
            guard observedPanGesture == nil else { return }
            for gesture in mapView.gestureRecognizers ?? [] {
                switch gesture {
                case let pan as UIPanGestureRecognizer:
                    pan.addTarget(self, action: #selector(handleMapGesture(_:)))
                    observedPanGesture = pan
                case let pinch as UIPinchGestureRecognizer:
                    pinch.addTarget(self, action: #selector(handleMapGesture(_:)))
                    observedPinchGesture = pinch
                case let rotation as UIRotationGestureRecognizer:
                    rotation.addTarget(self, action: #selector(handleMapGesture(_:)))
                    observedRotationGesture = rotation
                default:
                    break
                }
            }
        }

        @objc private func handleMapGesture(_ gesture: UIGestureRecognizer) {
            guard gesture.state == .began, !isProgrammaticRegionChange else { return }
            parent.onUserInteraction()
        }

        func needsOverlayRefresh(parent: MapCanvasView) -> Bool {
            !parent.trackedPolylines.isEmpty != lastHadTracked || (parent.route != nil) != lastHadRoute
        }

        func shouldApplyIdleViewport(
            parent: MapCanvasView,
            followChanged: Bool,
            routeChanged: Bool = false,
            highlightChanged: Bool = false
        ) -> Bool {
            if routeChanged || highlightChanged { return true }
            if followChanged && parent.followUser { return true }
            return false
        }

        func recordIdleViewport(parent: MapCanvasView) {
            idleViewportKey = idleViewportKey(for: parent)
        }

        private func idleViewportKey(for parent: MapCanvasView) -> String {
            let routeID = MapCanvasView.routeFingerprint(for: parent.route)
            let highlight = parent.highlightedTrackSegmentIndex.map(String.init) ?? "none"
            let region = parent.region
            return "\(routeID)-\(highlight)-\(parent.isNavigating)-\(region.center.latitude)-\(region.center.longitude)-\(region.span.latitudeDelta)"
        }

        func refreshUserLocationAnnotation(on mapView: MKMapView) {
            mapView.showsUserLocation = false
            mapView.showsUserLocation = true
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation {
                guard !parent.vehicleType.usesSystemUserLocation else { return nil }

                let identifier = "CustomUserLocation"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                    ?? MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)

                view.annotation = annotation
                view.canShowCallout = false
                let symbolConfig = UIImage.SymbolConfiguration(pointSize: 24, weight: .semibold)
                let image = UIImage(
                    systemName: parent.vehicleType.symbolName,
                    withConfiguration: symbolConfig
                )?.withTintColor(.systemBlue, renderingMode: .alwaysOriginal)
                view.image = image
                view.centerOffset = CGPoint(x: 0, y: -((image?.size.height ?? 24) / 2))
                return view
            }

            guard let pin = annotation as? MapPinAnnotation else { return nil }

            let identifier: String
            let color: UIColor
            let glyphName: String
            switch pin.role {
            case .start:
                identifier = "StartPin"
                color = .systemBlue
                glyphName = "location.fill"
            case .destination:
                identifier = "DestinationPin"
                color = .systemRed
                glyphName = "mappin"
            }

            let marker = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            marker.annotation = annotation
            marker.canShowCallout = false
            marker.markerTintColor = color
            marker.glyphTintColor = .white
            marker.glyphImage = UIImage(systemName: glyphName)
            marker.titleVisibility = .visible
            marker.displayPriority = .required
            return marker
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                if polyline.title?.hasPrefix("tracked") == true {
                    let isHighlighted = parent.highlightedTrackSegmentIndex.map { polyline.title == "tracked-\($0)" } ?? false
                    if isHighlighted {
                        renderer.strokeColor = UIColor.systemYellow.withAlphaComponent(0.95)
                        renderer.lineWidth = 8
                    } else {
                        renderer.strokeColor = parent.trackedColor.withAlphaComponent(0.85)
                        renderer.lineWidth = 5
                    }
                } else {
                    renderer.strokeColor = parent.routeColor
                    renderer.lineWidth = 6
                }
                renderer.lineCap = .round
                renderer.lineJoin = .round
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            guard !isProgrammaticRegionChange else { return }
            if parent.followUser, mapView.userTrackingMode == .none {
                parent.onUserInteraction()
            }
        }
    }
}
