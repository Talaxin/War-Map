import CoreLocation
import Foundation

enum DistanceFormatting {
    private static let formatter: MeasurementFormatter = {
        let f = MeasurementFormatter()
        f.unitOptions = .naturalScale
        f.unitStyle = .short
        f.numberFormatter.maximumFractionDigits = 0
        return f
    }()

    static func format(distance: CLLocationDistance) -> String {
        let meters = Measurement(value: distance, unit: UnitLength.meters)
        let locale = Locale.current
        if locale.usesMetricSystem {
            if distance < 1000 {
                return formatter.string(from: meters.converted(to: .meters))
            }
            return formatter.string(from: meters.converted(to: .kilometers))
        }
        let feet = meters.converted(to: .feet)
        if distance < 1609 {
            return formatter.string(from: feet)
        }
        return formatter.string(from: meters.converted(to: .miles))
    }

    static func format(duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = duration >= 3600 ? [.hour, .minute] : [.minute]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .dropLeading
        return formatter.string(from: duration) ?? "—"
    }
}
