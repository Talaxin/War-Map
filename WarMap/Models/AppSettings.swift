import AVFoundation
import Combine
import SwiftUI
import UIKit

enum VehicleType: String, CaseIterable, Identifiable {
    case blueDot
    case car
    case suv
    case truck

    var id: String { rawValue }

    var label: String {
        switch self {
        case .blueDot: return "Blue dot"
        case .car: return "Car"
        case .suv: return "SUV"
        case .truck: return "Truck"
        }
    }

    var symbolName: String {
        switch self {
        case .blueDot: return "location.fill"
        case .car: return "car.fill"
        case .suv: return "car.2.fill"
        case .truck: return "truck.box.fill"
        }
    }

    var usesSystemUserLocation: Bool {
        self == .blueDot
    }
}

enum RouteColorOption: String, CaseIterable, Identifiable {
    case blue
    case green
    case orange
    case purple
    case red
    case gray

    var id: String { rawValue }

    var label: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .blue: return .blue
        case .green: return .green
        case .orange: return .orange
        case .purple: return .purple
        case .red: return .red
        case .gray: return .gray
        }
    }

    var uiColor: UIColor {
        switch self {
        case .blue: return .systemBlue
        case .green: return .systemGreen
        case .orange: return .systemOrange
        case .purple: return .systemPurple
        case .red: return .systemRed
        case .gray: return .systemGray
        }
    }
}

struct VoiceOption: Identifiable, Hashable {
    let id: String
    let name: String
    let identifier: String?

    static let systemDefault = VoiceOption(id: "default", name: "Default", identifier: nil)

    static func loadEnglishVoices() -> [VoiceOption] {
        let voices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
        let preferredNames = ["Samantha", "Daniel", "Karen", "Alex", "Fred", "Victoria"]
        var options = [systemDefault]
        var seen = Set<String>()
        for name in preferredNames {
            if let voice = voices.first(where: { $0.name == name }), seen.insert(voice.identifier).inserted {
                options.append(VoiceOption(id: voice.identifier, name: voice.name, identifier: voice.identifier))
            }
        }
        if options.count == 1 {
            for voice in voices.prefix(4) where seen.insert(voice.identifier).inserted {
                options.append(VoiceOption(id: voice.identifier, name: voice.name, identifier: voice.identifier))
            }
        }
        return options
    }
}

struct RoutePreferences: Equatable {
    var allowHighways: Bool
    var allowFerries: Bool
    var allowCrossBorder: Bool
    var allowTollRoads: Bool
}

@MainActor
final class AppSettings: ObservableObject {
    @Published var routeColor: RouteColorOption {
        didSet { persist(routeColor.rawValue, for: .routeColor) }
    }
    @Published var trackedColor: RouteColorOption {
        didSet { persist(trackedColor.rawValue, for: .trackedColor) }
    }
    @Published var vehicleType: VehicleType {
        didSet { persist(vehicleType.rawValue, for: .vehicleType) }
    }
    @Published var voiceGuidanceEnabled: Bool {
        didSet { persist(voiceGuidanceEnabled, for: .voiceEnabled) }
    }
    @Published var selectedVoiceID: String {
        didSet { persist(selectedVoiceID, for: .voiceID) }
    }
    @Published var newRoadPercent: Int {
        didSet { persist(newRoadPercent, for: .newRoadPercent) }
    }
    @Published var allowHighways: Bool {
        didSet { persist(allowHighways, for: .allowHighways) }
    }
    @Published var allowFerries: Bool {
        didSet { persist(allowFerries, for: .allowFerries) }
    }
    @Published var allowCrossBorder: Bool {
        didSet { persist(allowCrossBorder, for: .allowCrossBorder) }
    }
    @Published var allowTollRoads: Bool {
        didSet { persist(allowTollRoads, for: .allowTollRoads) }
    }

    let voiceOptions: [VoiceOption]

    private enum Key: String {
        case routeColor, trackedColor, vehicleType, voiceEnabled, voiceID, newRoadPercent
        case allowHighways, allowFerries, allowCrossBorder, allowTollRoads
    }

    init() {
        let defaults = UserDefaults.standard
        routeColor = RouteColorOption(rawValue: defaults.string(forKey: Key.routeColor.rawValue) ?? "") ?? .blue
        trackedColor = RouteColorOption(rawValue: defaults.string(forKey: Key.trackedColor.rawValue) ?? "") ?? .gray
        vehicleType = VehicleType(rawValue: defaults.string(forKey: Key.vehicleType.rawValue) ?? "") ?? .blueDot
        voiceGuidanceEnabled = defaults.object(forKey: Key.voiceEnabled.rawValue) as? Bool ?? false
        selectedVoiceID = defaults.string(forKey: Key.voiceID.rawValue) ?? VoiceOption.systemDefault.id
        newRoadPercent = defaults.object(forKey: Key.newRoadPercent.rawValue) as? Int ?? 50
        allowHighways = defaults.object(forKey: Key.allowHighways.rawValue) as? Bool ?? true
        allowFerries = defaults.object(forKey: Key.allowFerries.rawValue) as? Bool ?? true
        allowCrossBorder = defaults.object(forKey: Key.allowCrossBorder.rawValue) as? Bool ?? true
        allowTollRoads = defaults.object(forKey: Key.allowTollRoads.rawValue) as? Bool ?? true
        voiceOptions = VoiceOption.loadEnglishVoices()
    }

    var routePreferences: RoutePreferences {
        RoutePreferences(
            allowHighways: allowHighways,
            allowFerries: allowFerries,
            allowCrossBorder: allowCrossBorder,
            allowTollRoads: allowTollRoads
        )
    }

    private func persist(_ value: String, for key: Key) {
        UserDefaults.standard.set(value, forKey: key.rawValue)
    }

    private func persist(_ value: Bool, for key: Key) {
        UserDefaults.standard.set(value, forKey: key.rawValue)
    }

    private func persist(_ value: Int, for key: Key) {
        UserDefaults.standard.set(value, forKey: key.rawValue)
    }
}
