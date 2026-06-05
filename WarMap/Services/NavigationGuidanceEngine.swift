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
        state = NavigationGuidanceState(
            currentStepIndex: 0,
            instruction: firstInstruction(for: route),
            distanceToManeuver: route.steps.first?.distance ?? route.distance,
            remainingDistance: route.distance,
            remainingTime: route.expectedTravelTime,
            arrived: false
        )
    }

    func update(userLocation: CLLocation) -> Bool {
        guard let route, !route.steps.isEmpty else { return false }

        let steps = route.steps
        var index = min(state.currentStepIndex, steps.count - 1)

        while index < steps.count - 1 {
            let endDistance = distance(from: userLocation, toEndOf: steps[index])
            if endDistance > 35 {
                break
            }
            index += 1
        }

        let arrived = index >= steps.count - 1
            && distance(from: userLocation, toEndOf: steps[steps.count - 1]) < 40

        let step = steps[index]
        let distanceToTurn = max(distance(from: userLocation, toEndOf: step), 0)
        let remaining = estimateRemainingDistance(from: index, userLocation: userLocation, route: route)

        let previousIndex = state.currentStepIndex
        state = NavigationGuidanceState(
            currentStepIndex: index,
            instruction: arrived ? "You have arrived" : step.instructions,
            distanceToManeuver: arrived ? 0 : distanceToTurn,
            remainingDistance: remaining,
            remainingTime: estimateRemainingTime(remaining: remaining, route: route),
            arrived: arrived
        )

        let stepChanged = index != previousIndex || arrived
        return stepChanged
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

    private func firstInstruction(for route: MKRoute) -> String {
        route.steps.first(where: { !$0.instructions.isEmpty })?.instructions ?? "Head toward destination"
    }

    private func estimateRemainingDistance(from stepIndex: Int, userLocation: CLLocation, route: MKRoute) -> CLLocationDistance {
        let steps = route.steps
        guard stepIndex < steps.count else { return 0 }
        var total = distance(from: userLocation, toEndOf: steps[stepIndex])
        if stepIndex + 1 < steps.count {
            for idx in (stepIndex + 1)..<steps.count {
                total += steps[idx].distance
            }
        }
        return max(total, 0)
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
}
