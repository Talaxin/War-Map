import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    RouteAppearanceSettingsView(settings: settings)
                } label: {
                    SettingsRowLabel(
                        title: "Route Appearance",
                        subtitle: "\(settings.routeColor.label) route, \(settings.trackedColor.label) tracked",
                        systemImage: "point.topleft.down.curvedto.point.bottomright.up"
                    )
                }

                NavigationLink {
                    VehicleIconSettingsView(settings: settings)
                } label: {
                    SettingsRowLabel(
                        title: "Map Marker",
                        subtitle: settings.vehicleType.label,
                        systemImage: settings.vehicleType.symbolName
                    )
                }

                NavigationLink {
                    VoiceGuidanceSettingsView(settings: settings)
                } label: {
                    SettingsRowLabel(
                        title: "Voice Guidance",
                        subtitle: settings.voiceGuidanceEnabled ? "On" : "Off",
                        systemImage: "speaker.wave.2.fill"
                    )
                }

                NavigationLink {
                    NewRoadSettingsView(settings: settings)
                } label: {
                    SettingsRowLabel(
                        title: "New Road",
                        subtitle: "\(settings.newRoadPercent)%",
                        systemImage: "road.lanes"
                    )
                }

                NavigationLink {
                    RouteOptionsSettingsView(settings: settings)
                } label: {
                    SettingsRowLabel(
                        title: "Route Options",
                        subtitle: routeOptionsSummary,
                        systemImage: "arrow.triangle.turn.up.right.diamond.fill"
                    )
                }

                Section {
                    HStack {
                        Spacer()
                        Text("Version \(appVersion)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
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

    private var routeOptionsSummary: String {
        let enabled = [
            settings.allowHighways ? "Highways" : nil,
            settings.allowFerries ? "Ferries" : nil,
            settings.allowCrossBorder ? "Cross-border" : nil,
            settings.allowTollRoads ? "Tolls" : nil,
        ].compactMap { $0 }
        return enabled.isEmpty ? "None" : enabled.joined(separator: ", ")
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
}

private struct SettingsRowLabel: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body)
                .foregroundStyle(.blue)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct RouteAppearanceSettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
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
                .pickerStyle(.inline)

                Picker("Tracked roads", selection: $settings.trackedColor) {
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
                .pickerStyle(.inline)
            } footer: {
                Text("Route color is the active path to your destination. Tracked roads show where you have actually driven.")
            }
        }
        .navigationTitle("Route Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct VehicleIconSettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Picker("Map marker", selection: $settings.vehicleType) {
                    ForEach(VehicleType.allCases) { type in
                        Label(type.label, systemImage: type.symbolName)
                            .tag(type)
                    }
                }
                .pickerStyle(.inline)
            } footer: {
                Text("Blue dot uses the standard Apple Maps location marker. Other options replace it with a vehicle icon.")
            }
        }
        .navigationTitle("Map Marker")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct VoiceGuidanceSettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Toggle("Speak directions", isOn: $settings.voiceGuidanceEnabled)
            }
            if settings.voiceGuidanceEnabled {
                Section("Voice") {
                    Picker("Voice", selection: $settings.selectedVoiceID) {
                        ForEach(settings.voiceOptions) { voice in
                            Text(voice.name).tag(voice.id)
                        }
                    }
                    .pickerStyle(.inline)
                }
            }
        }
        .navigationTitle("Voice Guidance")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct NewRoadSettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
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
                }
            } footer: {
                Text("War Map remembers roads you have actually driven. At 0% you get the fastest route. Higher values require more untraveled distance along the trip — 50% on a 20 km route means at least 10 km of roads you have not driven. At 100% War Map picks the route with the most new roads; some overlap is unavoidable when only one path exists.")
            }
        }
        .navigationTitle("New Road")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct RouteOptionsSettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Toggle("Highways", isOn: $settings.allowHighways)
                Toggle("Ferries", isOn: $settings.allowFerries)
                Toggle("Cross-border", isOn: $settings.allowCrossBorder)
                Toggle("Toll roads", isOn: $settings.allowTollRoads)
            } footer: {
                Text("Choose which road types War Map may include when calculating routes.")
            }
        }
        .navigationTitle("Route Options")
        .navigationBarTitleDisplayMode(.inline)
    }
}
