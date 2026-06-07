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
        let meters = Measurement(value: distance, unit: UnitLength.meters)
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

    static func format(duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = duration >= 3600 ? [.hour, .minute] : [.minute]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .dropLeading
        return formatter.string(from: duration) ?? "—"
    }
}
