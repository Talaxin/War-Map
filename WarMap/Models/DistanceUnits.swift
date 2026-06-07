import Foundation

enum DistanceUnitSystem: String, CaseIterable, Identifiable {
    case metric
    case imperial
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .metric: return "Metric"
        case .imperial: return "Imperial"
        case .custom: return "Custom"
        }
    }
}

enum ShortDistanceUnit: String, CaseIterable, Identifiable {
    case meters
    case feet

    var id: String { rawValue }

    var label: String {
        switch self {
        case .meters: return "Meters"
        case .feet: return "Feet"
        }
    }
}

enum LongDistanceUnit: String, CaseIterable, Identifiable {
    case kilometers
    case miles

    var id: String { rawValue }

    var label: String {
        switch self {
        case .kilometers: return "Kilometers"
        case .miles: return "Miles"
        }
    }
}

struct DistanceUnitPreferences: Equatable {
    var system: DistanceUnitSystem
    var shortUnit: ShortDistanceUnit
    var longUnit: LongDistanceUnit

    private static var prefersMetric: Bool {
        Locale.current.measurementSystem == .metric
    }

    static let `default` = DistanceUnitPreferences(
        system: prefersMetric ? .metric : .imperial,
        shortUnit: prefersMetric ? .meters : .feet,
        longUnit: prefersMetric ? .kilometers : .miles
    )

    var summary: String {
        switch system {
        case .metric:
            return "Meters & kilometers"
        case .imperial:
            return "Feet & miles"
        case .custom:
            return "\(shortUnit.label) & \(longUnit.label)"
        }
    }
}
