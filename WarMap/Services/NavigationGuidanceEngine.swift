import CoreLocation
import Foundation
import MapKit

struct NavigationGuidanceState: Equatable {
    var currentStepIndex: Int = 0
    var instruction: String = ""
    var distanceToManeuver: CLLocationDistance = 0
    var remainingDistance: CLLocationDistance = 0
    var remainingTime: TimeInterval = 0
    var arrived: Bool = false
}

@MainActor
final class NavigationGuidanceEngine {
    private(set) var state = NavigationGuidanceState()
    private var route: MKRoute?
    private var announcedStepIndex: Int?

    func reset() {
        route = nil
        announcedStepIndex = nil
        state = NavigationGuidanceState()
    }

    func load(route: MKRoute) {
        self.route = route
        announcedStepIndex = nil
        let steps = meaningfulSteps(from: route)
        state = NavigationGuidanceState(
            currentStepIndex: 0,
            instruction: firstInstruction(for: route),
            distanceToManeuver: steps.first?.distance ?? route.distance,
            remainingDistance: route.distance,
            remainingTime: route.expectedTravelTime,
            arrived: false
        )
    }

    func update(userLocation: CLLocation) -> Bool {
        guard let route else { return false }
        let steps = meaningfulSteps(from: route)
        guard !steps.isEmpty else { return false }

        var index = min(state.currentStepIndex, steps.count - 1)

        // Snap forward to whichever upcoming step polyline we're closest to.
        for stepIndex in index..<steps.count {
            let distanceToStep = distanceFrom(userLocation, toPolyline: steps[stepIndex].polyline)
            if distanceToStep <= 120 {
                index = stepIndex
            }
        }

        // Advance through steps we've passed or clearly left behind.
        while index < steps.count - 1 {
            let distToEnd = distanceAlongStepToEnd(from: userLocation, step: steps[index])
            let straightToEnd = distance(from: userLocation, toEndOf: steps[index])
            let distToNext = distanceFrom(userLocation, toPolyline: steps[index + 1].polyline)
            let distToCurrent = distanceFrom(userLocation, toPolyline: steps[index].polyline)

            let passedManeuver = straightToEnd < 45 || distToEnd < 45
            let leftStepBehind = distToNext + 20 < distToCurrent && distToNext < 80

            if passedManeuver || leftStepBehind {
                index += 1
            } else {
                break
            }
        }

        let arrived = index >= steps.count - 1
            && distance(from: userLocation, toEndOf: steps[steps.count - 1]) < 45

        let step = steps[index]
        let distanceToTurn = arrived ? 0 : max(distanceAlongStepToEnd(from: userLocation, step: step), 0)
        let remaining = estimateRemainingDistance(from: index, userLocation: userLocation, steps: steps, route: route)

        let previousIndex = state.currentStepIndex
        state = NavigationGuidanceState(
            currentStepIndex: index,
            instruction: arrived ? "You have arrived" : step.instructions,
            distanceToManeuver: distanceToTurn,
            remainingDistance: remaining,
            remainingTime: estimateRemainingTime(remaining: remaining, route: route),
            arrived: arrived
        )

        return index != previousIndex || arrived
    }

    func shouldAnnounceStep() -> String? {
        guard !state.arrived else { return announcedStepIndex == -1 ? nil : state.instruction }
        let index = state.currentStepIndex
        guard announcedStepIndex != index else { return nil }
        announcedStepIndex = index
        return state.instruction
    }

    func markArrivalAnnounced() {
        announcedStepIndex = -1
    }

    private func meaningfulSteps(from route: MKRoute) -> [MKRoute.Step] {
        route.steps.filter { !$0.instructions.isEmpty || $0.distance > 1 }
    }

    private func firstInstruction(for route: MKRoute) -> String {
        meaningfulSteps(from: route).first?.instructions ?? "Head toward destination"
    }

    private func estimateRemainingDistance(
        from stepIndex: Int,
        userLocation: CLLocation,
        steps: [MKRoute.Step],
        route: MKRoute
    ) -> CLLocationDistance {
        guard stepIndex < steps.count else { return 0 }
        var total = distanceAlongStepToEnd(from: userLocation, step: steps[stepIndex])
        if stepIndex + 1 < steps.count {
            for idx in (stepIndex + 1)..<steps.count {
                total += steps[idx].distance
            }
        }
        return max(min(total, route.distance), 0)
    }

    private func estimateRemainingTime(remaining: CLLocationDistance, route: MKRoute) -> TimeInterval {
        guard route.distance > 0 else { return 0 }
        let ratio = remaining / route.distance
        return route.expectedTravelTime * ratio
    }

    private func distance(from location: CLLocation, toEndOf step: MKRoute.Step) -> CLLocationDistance {
        guard step.polyline.pointCount > 0 else { return step.distance }
        let points = step.polyline.points()
        let last = points[step.polyline.pointCount - 1].coordinate
        return location.distance(from: CLLocation(latitude: last.latitude, longitude: last.longitude))
    }

    private func distanceFrom(_ location: CLLocation, toPolyline polyline: MKPolyline) -> CLLocationDistance {
        guard polyline.pointCount >= 2 else { return .greatestFiniteMagnitude }
        let points = polyline.points()
        var minimum = CLLocationDistance.greatestFiniteMagnitude
        for index in 1..<polyline.pointCount {
            let start = points[index - 1].coordinate
            let end = points[index].coordinate
            minimum = min(minimum, distanceFrom(location, toSegmentFrom: start, to: end))
        }
        return minimum
    }

    private func distanceFrom(
        _ location: CLLocation,
        toSegmentFrom start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D
    ) -> CLLocationDistance {
        let startPoint = MKMapPoint(start)
        let endPoint = MKMapPoint(end)
        let userPoint = MKMapPoint(location.coordinate)
        let dx = endPoint.x - startPoint.x
        let dy = endPoint.y - startPoint.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else {
            return userPoint.distance(to: startPoint)
        }
        let t = max(0, min(1, ((userPoint.x - startPoint.x) * dx + (userPoint.y - startPoint.y) * dy) / lengthSquared))
        let projected = MKMapPoint(x: startPoint.x + t * dx, y: startPoint.y + t * dy)
        return userPoint.distance(to: projected)
    }

    private func distanceAlongStepToEnd(from location: CLLocation, step: MKRoute.Step) -> CLLocationDistance {
        let polyline = step.polyline
        guard polyline.pointCount >= 2 else { return step.distance }

        let points = polyline.points()
        let userPoint = MKMapPoint(location.coordinate)
        var bestRemaining = step.distance
        var foundProjection = false

        for index in 1..<polyline.pointCount {
            let start = points[index - 1]
            let end = points[index]
            let startPoint = MKMapPoint(start.coordinate)
            let endPoint = MKMapPoint(end.coordinate)
            let dx = endPoint.x - startPoint.x
            let dy = endPoint.y - startPoint.y
            let lengthSquared = dx * dx + dy * dy
            guard lengthSquared > 0 else { continue }

            let t = max(0, min(1, ((userPoint.x - startPoint.x) * dx + (userPoint.y - startPoint.y) * dy) / lengthSquared))
            let projected = MKMapPoint(x: startPoint.x + t * dx, y: startPoint.y + t * dy)
            let distanceToSegment = userPoint.distance(to: projected)
            guard distanceToSegment < 120 else { continue }

            var segmentRemaining = projected.distance(to: endPoint)
            for tailIndex in (index + 1)..<polyline.pointCount {
                let previous = MKMapPoint(points[tailIndex - 1].coordinate)
                let next = MKMapPoint(points[tailIndex].coordinate)
                segmentRemaining += previous.distance(to: next)
            }
            if !foundProjection || distanceToSegment < 80 {
                bestRemaining = segmentRemaining
                foundProjection = true
            }
        }

        if foundProjection {
            return max(bestRemaining, 0)
        }
        return distance(from: location, toEndOf: step)
    }
}
