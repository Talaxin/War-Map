import MapKit
import SwiftUI

struct MapCanvasView: UIViewRepresentable {
    let region: MKCoordinateRegion
    let start: MapPlace?
    let destination: MapPlace?

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.isRotateEnabled = false
        mapView.showsUserLocation = true
        mapView.pointOfInterestFilter = .includingAll
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        mapView.setRegion(region, animated: true)
        mapView.removeAnnotations(mapView.annotations.filter { !($0 is MKUserLocation) })
        if let start {
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
    }
}
