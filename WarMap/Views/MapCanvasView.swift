import MapKit
import SwiftUI

struct MapCanvasView: UIViewRepresentable {
    let region: MKCoordinateRegion
    let route: MKRoute?
    let start: MapPlace?
    let destination: MapPlace?
    let isNavigating: Bool
    let followUser: Bool

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

        if followUser, isNavigating {
            mapView.setUserTrackingMode(.follow, animated: true)
        } else {
            mapView.setUserTrackingMode(.none, animated: true)
            if let route, !isNavigating {
                let padding = UIEdgeInsets(top: 120, left: 48, bottom: 200, right: 48)
                mapView.setVisibleMapRect(route.polyline.boundingMapRect, edgePadding: padding, animated: true)
            } else {
                mapView.setRegion(region, animated: true)
            }
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapCanvasView

        init(parent: MapCanvasView) {
            self.parent = parent
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor.systemBlue
                renderer.lineWidth = 6
                renderer.lineCap = .round
                renderer.lineJoin = .round
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}
