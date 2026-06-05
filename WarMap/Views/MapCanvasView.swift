import MapKit
import SwiftUI

struct MapCanvasView: UIViewRepresentable {
    let region: MKCoordinateRegion
    let route: MKRoute?
    let start: MapPlace?
    let destination: MapPlace?
    let isNavigating: Bool
    let followUser: Bool
    let routeColor: UIColor
    let vehicleType: VehicleType
    let recenterToken: Int
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
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.parent = self

        if context.coordinator.lastVehicleType != vehicleType {
            context.coordinator.lastVehicleType = vehicleType
            context.coordinator.refreshUserLocationAnnotation(on: mapView)
        }

        mapView.removeOverlays(mapView.overlays)
        if let route {
            mapView.addOverlay(route.polyline)
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

        context.coordinator.isProgrammaticRegionChange = true
        if followUser, isNavigating {
            mapView.setUserTrackingMode(.follow, animated: true)
        } else {
            if mapView.userTrackingMode != .none {
                mapView.setUserTrackingMode(.none, animated: false)
            }
            if recenterToken != context.coordinator.lastRecenterToken {
                context.coordinator.lastRecenterToken = recenterToken
                if let coordinate = mapView.userLocation.location?.coordinate {
                    let region = MKCoordinateRegion(
                        center: coordinate,
                        latitudinalMeters: 1_200,
                        longitudinalMeters: 1_200
                    )
                    mapView.setRegion(region, animated: true)
                }
            } else if let route, !isNavigating {
                let padding = UIEdgeInsets(top: 120, left: 48, bottom: 200, right: 48)
                mapView.setVisibleMapRect(route.polyline.boundingMapRect, edgePadding: padding, animated: true)
            } else if !isNavigating {
                mapView.setRegion(region, animated: true)
            }
        }
        DispatchQueue.main.async {
            context.coordinator.isProgrammaticRegionChange = false
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapCanvasView
        var lastRecenterToken = -1
        var lastVehicleType: VehicleType?
        var isProgrammaticRegionChange = false

        init(parent: MapCanvasView) {
            self.parent = parent
            lastVehicleType = parent.vehicleType
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
                renderer.strokeColor = parent.routeColor
                renderer.lineWidth = 6
                renderer.lineCap = .round
                renderer.lineJoin = .round
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            guard parent.isNavigating, parent.followUser, !isProgrammaticRegionChange else { return }
            parent.onUserInteraction()
        }
    }
}
