import CoreLocation
import MapKit

struct RoadSnapMatch {
    let coordinate: CLLocationCoordinate2D
    let distance: CLLocationDistance
    let segmentBearing: CLLocationDirection?
}

enum RoadSnapper {
    static let navigationMaxDistance: CLLocationDistance = 80
    static let trackingMaxDistance: CLLocationDistance = 40

    static func snap(
        _ coordinate: CLLocationCoordinate2D,
        routePolyline: MKPolyline?,
        trackedPolylines: [MKPolyline],
        preferRoute: Bool,
        maxDistance: CLLocationDistance
    ) -> RoadSnapMatch? {
        if preferRoute, let routePolyline,
           let match = closestPoint(on: routePolyline, to: coordinate),
           match.distance <= maxDistance {
            return match
        }

        var best: RoadSnapMatch?
        for polyline in trackedPolylines {
            guard let match = closestPoint(on: polyline, to: coordinate) else { continue }
            if best == nil || match.distance < best!.distance {
                best = match
            }
        }

        if let best, best.distance <= maxDistance {
            return best
        }

        if !preferRoute, let routePolyline,
           let match = closestPoint(on: routePolyline, to: coordinate),
           match.distance <= maxDistance {
            return match
        }

        return nil
    }

    static func closestPoint(
        on polyline: MKPolyline,
        to coordinate: CLLocationCoordinate2D
    ) -> RoadSnapMatch? {
        guard polyline.pointCount >= 2 else { return nil }

        let userPoint = MKMapPoint(coordinate)
        let points = polyline.points()
        var bestDistance = CLLocationDistance.greatestFiniteMagnitude
        var bestCoordinate: CLLocationCoordinate2D?
        var bestBearing: CLLocationDirection?

        for index in 1..<polyline.pointCount {
            let start = points[index - 1].coordinate
            let end = points[index].coordinate
            let startPoint = MKMapPoint(start)
            let endPoint = MKMapPoint(end)
            let dx = endPoint.x - startPoint.x
            let dy = endPoint.y - startPoint.y
            let lengthSquared = dx * dx + dy * dy

            let projected: MKMapPoint
            if lengthSquared > 0 {
                let t = max(
                    0,
                    min(1, ((userPoint.x - startPoint.x) * dx + (userPoint.y - startPoint.y) * dy) / lengthSquared)
                )
                projected = MKMapPoint(x: startPoint.x + t * dx, y: startPoint.y + t * dy)
            } else {
                projected = startPoint
            }

            let distance = userPoint.distance(to: projected)
            if distance < bestDistance {
                bestDistance = distance
                bestCoordinate = projected.coordinate
                bestBearing = bearing(from: start, to: end)
            }
        }

        guard let bestCoordinate else { return nil }
        return RoadSnapMatch(
            coordinate: bestCoordinate,
            distance: bestDistance,
            segmentBearing: bestBearing
        )
    }

    private static func bearing(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D
    ) -> CLLocationDirection {
        let lat1 = start.latitude * .pi / 180
        let lat2 = end.latitude * .pi / 180
        let deltaLon = (end.longitude - start.longitude) * .pi / 180
        let y = sin(deltaLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
        let radians = atan2(y, x)
        let degrees = radians * 180 / .pi
        return degrees >= 0 ? degrees : degrees + 360
    }
}
