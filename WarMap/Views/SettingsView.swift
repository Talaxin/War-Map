import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section("Route appearance") {
                    Picker("Route color", selection: $settings.routeColor) {
                        ForEach(RouteColorOption.allCases) { option in
                            HStack {
                                Circle()
                                    .fill(option.color)
                                    .frame(width: 14, height: 14)
                                Text(option.label)
                            }
                            .tag(option)
                        }
                    }

                    Picker("Vehicle icon", selection: $settings.vehicleType) {
                        ForEach(VehicleType.allCases) { type in
                            Label(type.label, systemImage: type.symbolName)
                                .tag(type)
                        }
                    }
                }

                Section("Voice guidance") {
                    Toggle("Speak directions", isOn: $settings.voiceGuidanceEnabled)
                    if settings.voiceGuidanceEnabled {
                        Picker("Voice", selection: $settings.selectedVoiceID) {
                            ForEach(settings.voiceOptions) { voice in
                                Text(voice.name).tag(voice.id)
                            }
                        }
                    }
                }

                Section("New Road") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Preference")
                            Spacer()
                            Text("\(settings.newRoadPercent)%")
                                .foregroundStyle(.secondary)
                        }
                        Slider(
                            value: Binding(
                                get: { Double(settings.newRoadPercent) },
                                set: { settings.newRoadPercent = Int(($0 / 10).rounded() * 10) }
                            ),
                            in: 0...100,
                            step: 10
                        )
                        Text("Routing impact coming soon.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Route options") {
                    Toggle("Highways", isOn: $settings.allowHighways)
                    Toggle("Ferries", isOn: $settings.allowFerries)
                    Toggle("Cross-border", isOn: $settings.allowCrossBorder)
                    Toggle("Toll roads", isOn: $settings.allowTollRoads)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
