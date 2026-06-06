import MapKit
import SwiftUI

struct MapCanvasView: UIViewRepresentable {
    let region: MKCoordinateRegion
    let route: MKRoute?
    let trackedPolyline: MKPolyline?
    let start: MapPlace?
    let destination: MapPlace?
    let isNavigating: Bool
    let followUser: Bool
    let trackingMode: MapTrackingMode
    let routeColor: UIColor
    let trackedColor: UIColor
    let vehicleType: VehicleType
    let trackedPathRevision: Int
    var onUserInteraction: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.isRotateEnabled = false
        mapView.showsUserLocation = true
        mapView.showsCompass = true
        mapView.pointOfInterestFilter = .includingAll
        context.coordinator.installPanObserver(on: mapView)
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

        if revisionChanged
            || context.coordinator.needsOverlayRefresh(parent: self)
            || context.coordinator.lastRouteColor != routeColor
            || context.coordinator.lastTrackedColor != trackedColor {
            mapView.removeOverlays(mapView.overlays)
            if let trackedPolyline {
                mapView.addOverlay(trackedPolyline, level: .aboveRoads)
            }
            if let route {
                let polyline = route.polyline
                polyline.title = "route"
                mapView.addOverlay(polyline, level: .aboveRoads)
            }
            context.coordinator.lastHadTracked = trackedPolyline != nil
            context.coordinator.lastHadRoute = route != nil
            context.coordinator.lastRouteColor = routeColor
            context.coordinator.lastTrackedColor = trackedColor
        }

        mapView.removeAnnotations(mapView.annotations.filter { !($0 is MKUserLocation) })
        if let start, !isNavigating {
            let annotation = MKPointAnnotation()
            annotation.coordinate = start.coordinate
            annotation.title = start.title
            mapView.addAnnotation(annotation)
        }
        if let destination {
            let annotation = MKPointAnnotation()
            annotation.coordinate = destination.coordinate
            annotation.title = destination.title
            mapView.addAnnotation(annotation)
        }

        let followChanged = followUser != context.coordinator.lastFollowUser
        let trackingModeChanged = trackingMode != context.coordinator.lastTrackingMode

        if followUser {
            mapView.isRotateEnabled = trackingMode == .followWithHeading
            let mode: MKUserTrackingMode = trackingMode == .followWithHeading ? .followWithHeading : .follow
            if mapView.userTrackingMode != mode || followChanged || trackingModeChanged {
                context.coordinator.setProgrammaticChange(true)
                mapView.setUserTrackingMode(mode, animated: followChanged || trackingModeChanged)
                context.coordinator.setProgrammaticChange(false)
            }
        } else {
            mapView.isRotateEnabled = false
            if mapView.userTrackingMode != .none {
                context.coordinator.setProgrammaticChange(true)
                mapView.setUserTrackingMode(.none, animated: false)
                context.coordinator.setProgrammaticChange(false)
            }

            if context.coordinator.shouldApplyIdleViewport(parent: self, followChanged: followChanged) {
                context.coordinator.setProgrammaticChange(true)
                if let route, !isNavigating {
                    let padding = UIEdgeInsets(top: 120, left: 48, bottom: 200, right: 48)
                    mapView.setVisibleMapRect(
                        route.polyline.boundingMapRect,
                        edgePadding: padding,
                        animated: followChanged
                    )
                } else if !isNavigating {
                    mapView.setRegion(region, animated: followChanged)
                }
                context.coordinator.recordIdleViewport(parent: self)
                context.coordinator.setProgrammaticChange(false)
            }
        }

        context.coordinator.lastFollowUser = followUser
        context.coordinator.lastTrackingMode = trackingMode
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapCanvasView
        var lastVehicleType: VehicleType?
        var lastTrackedPathRevision = -1
        var lastHadTracked = false
        var lastHadRoute = false
        var lastRouteColor: UIColor?
        var lastTrackedColor: UIColor?
        var lastFollowUser = true
        var lastTrackingMode: MapTrackingMode = .follow
        var idleViewportKey: String?
        private var isProgrammaticRegionChange = false
        private var programmaticChangeDepth = 0
        private weak var observedPanGesture: UIPanGestureRecognizer?

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

        func installPanObserver(on mapView: MKMapView) {
            guard observedPanGesture == nil else { return }
            for case let pan as UIPanGestureRecognizer in mapView.gestureRecognizers ?? [] {
                pan.addTarget(self, action: #selector(handlePan(_:)))
                observedPanGesture = pan
                break
            }
        }

        @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard gesture.state == .began, parent.followUser, !isProgrammaticRegionChange else { return }
            parent.onUserInteraction()
        }

        func needsOverlayRefresh(parent: MapCanvasView) -> Bool {
            (parent.trackedPolyline != nil) != lastHadTracked || (parent.route != nil) != lastHadRoute
        }

        func shouldApplyIdleViewport(parent: MapCanvasView, followChanged: Bool) -> Bool {
            if followChanged { return true }
            let key = idleViewportKey(for: parent)
            return key != idleViewportKey
        }

        func recordIdleViewport(parent: MapCanvasView) {
            idleViewportKey = idleViewportKey(for: parent)
        }

        private func idleViewportKey(for parent: MapCanvasView) -> String {
            let routeID: String
            if let route = parent.route {
                routeID = "\(route.distance)-\(route.expectedTravelTime)-\(route.polyline.pointCount)"
            } else {
                routeID = "none"
            }
            let region = parent.region
            return "\(routeID)-\(parent.isNavigating)-\(region.center.latitude)-\(region.center.longitude)-\(region.span.latitudeDelta)"
        }

        func refreshUserLocationAnnotation(on mapView: MKMapView) {
            mapView.showsUserLocation = false
            mapView.showsUserLocation = true
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard annotation is MKUserLocation else { return nil }
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

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                if polyline.title == "tracked" {
                    renderer.strokeColor = parent.trackedColor.withAlphaComponent(0.85)
                    renderer.lineWidth = 5
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
            guard parent.followUser, !isProgrammaticRegionChange else { return }
            if mapView.userTrackingMode == .none {
                parent.onUserInteraction()
            }
        }
    }
}
