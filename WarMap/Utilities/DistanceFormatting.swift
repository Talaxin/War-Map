import CoreLocation
import Foundation

enum DistanceFormatting {
    private static let formatter: MeasurementFormatter = {
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .providedUnit
        formatter.unitStyle = .short
        formatter.numberFormatter.maximumFractionDigits = 0
        return formatter
    }()

    static func format(distance: CLLocationDistance, preferences: DistanceUnitPreferences) -> String {
        let meters = Measurement(value: max(0, distance), unit: UnitLength.meters)
        let shortThreshold: CLLocationDistance
        let shortUnit: UnitLength
        let longUnit: UnitLength

        switch preferences.system {
        case .metric:
            shortThreshold = 1000
            shortUnit = .meters
            longUnit = .kilometers
        case .imperial:
            shortThreshold = 1609
            shortUnit = .feet
            longUnit = .miles
        case .custom:
            shortUnit = preferences.shortUnit == .meters ? .meters : .feet
            longUnit = preferences.longUnit == .kilometers ? .kilometers : .miles
            shortThreshold = preferences.longUnit == .kilometers ? 1000 : 1609
        }

        if distance < shortThreshold {
            return formatter.string(from: meters.converted(to: shortUnit))
        }
        return formatter.string(from: meters.converted(to: longUnit))
    }

    /// Rounded travel time, matching Apple Maps-style minute labels.
    static func format(duration: TimeInterval) -> String {
        let roundedMinutes = max(1, Int((duration / 60.0).rounded()))
        if roundedMinutes >= 60 {
            let hours = roundedMinutes / 60
            let minutes = roundedMinutes % 60
            if minutes == 0 {
                return "\(hours) hr"
            }
            return "\(hours) hr \(minutes) min"
        }
        return "\(roundedMinutes) min"
    }

    /// Extra time vs the fastest route — always rounds up to at least 1 minute when slower.
    static func formatAdditionalDuration(_ duration: TimeInterval) -> String {
        guard duration >= 15 else { return "0 min" }
        let minutes = max(1, Int((duration / 60.0).rounded(.up)))
        return "\(minutes) min"
    }

    /// Extra distance vs the fastest route (only when longer).
    static func formatAdditionalDistance(
        _ delta: CLLocationDistance,
        preferences: DistanceUnitPreferences
    ) -> String {
        guard delta >= 100 else { return format(distance: 0, preferences: preferences) }
        return format(distance: delta, preferences: preferences)
    }
}
