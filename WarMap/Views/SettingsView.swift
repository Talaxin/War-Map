import MapKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var locationManager: LocationManager
    var currentDestination: MapPlace?
    var onSelectSavedDestination: (SavedLocation) -> Void = { _ in }
    var onSaveCurrentDestination: (String) -> Void = { _ in }
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
                    DistanceUnitsSettingsView(settings: settings)
                } label: {
                    SettingsRowLabel(
                        title: "Units",
                        subtitle: settings.distanceUnitPreferences.summary,
                        systemImage: "ruler"
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

                NavigationLink {
                    SavedLocationsSettingsView(
                        settings: settings,
                        currentDestination: currentDestination,
                        onSelect: { location in
                            onSelectSavedDestination(location)
                            dismiss()
                        },
                        onSaveCurrent: onSaveCurrentDestination
                    )
                } label: {
                    SettingsRowLabel(
                        title: "Destination Pin",
                        subtitle: savedLocationsSummary,
                        systemImage: "mappin.and.ellipse"
                    )
                }

                NavigationLink {
                    PastRoutesSettingsView(
                        locationManager: locationManager,
                        distancePreferences: settings.distanceUnitPreferences
                    )
                } label: {
                    SettingsRowLabel(
                        title: "Past Routes",
                        subtitle: pastRoutesSummary,
                        systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90"
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

    private var pastRoutesSummary: String {
        let count = locationManager.drivenPathSummaries.count
        return count == 0 ? "None saved" : "\(count) saved"
    }

    private var savedLocationsSummary: String {
        let count = settings.savedLocations.locations.count
        return count == 0 ? "None saved" : "\(count) saved"
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

private struct DistanceUnitsSettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Picker("Preset", selection: $settings.distanceUnitSystem) {
                    ForEach(DistanceUnitSystem.allCases) { system in
                        Text(system.label).tag(system)
                    }
                }
                .pickerStyle(.inline)
            } footer: {
                Text("Metric uses meters and kilometers. Imperial uses feet and miles. Custom lets you mix short and long units.")
            }

            if settings.distanceUnitSystem == .custom {
                Section("Short distances") {
                    Picker("Short unit", selection: $settings.customShortDistanceUnit) {
                        ForEach(ShortDistanceUnit.allCases) { unit in
                            Text(unit.label).tag(unit)
                        }
                    }
                    .pickerStyle(.inline)
                }

                Section("Long distances") {
                    Picker("Long unit", selection: $settings.customLongDistanceUnit) {
                        ForEach(LongDistanceUnit.allCases) { unit in
                            Text(unit.label).tag(unit)
                        }
                    }
                    .pickerStyle(.inline)
                }
            }
        }
        .navigationTitle("Units")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SavedLocationsSettingsView: View {
    @ObservedObject var settings: AppSettings
    let currentDestination: MapPlace?
    let onSelect: (SavedLocation) -> Void
    let onSaveCurrent: (String) -> Void

    @State private var showAddLocation = false
    @State private var showSaveCurrent = false

    var body: some View {
        Group {
            if settings.savedLocations.locations.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No saved destinations")
                        .font(.headline)
                    Text("Save places you visit often with a custom name, then pick them here to navigate.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button("Add destination") {
                        showAddLocation = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(settings.savedLocations.locations) { location in
                        Button {
                            onSelect(location)
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(location.name)
                                    Text(location.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                settings.savedLocations.delete(id: location.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Destination Pin")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddLocation = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add destination")
            }
            if currentDestination != nil {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Save current") {
                        showSaveCurrent = true
                    }
                }
            }
        }
        .sheet(isPresented: $showAddLocation) {
            AddSavedLocationView(settings: settings)
        }
        .alert("Save current destination", isPresented: $showSaveCurrent) {
            TextField("Name", text: $saveCurrentName)
            Button("Save") {
                let trimmed = saveCurrentName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                onSaveCurrent(trimmed)
                saveCurrentName = ""
            }
            Button("Cancel", role: .cancel) {
                saveCurrentName = ""
            }
        } message: {
            if let currentDestination {
                Text("Save “\(currentDestination.title)” as a favorite destination.")
            }
        }
    }

    @State private var saveCurrentName = ""
}

private struct AddSavedLocationView: View {
    @ObservedObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var searchQuery = ""
    @State private var searchError: String?
    @State private var isResolving = false
    @StateObject private var searchService = AddressSearchService()

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Home, Work, Gym…", text: $name)
                        .textInputAutocapitalization(.words)
                }

                Section("Location") {
                    TextField("Search address or place", text: $searchQuery)
                        .textInputAutocapitalization(.words)
                        .onChange(of: searchQuery) { newValue in
                            searchService.updateQuery(newValue, near: nil, localityHint: nil)
                        }

                    if isResolving {
                        HStack {
                            ProgressView()
                            Text("Resolving…")
                                .foregroundStyle(.secondary)
                        }
                    }

                    ForEach(Array(searchService.completions.enumerated()), id: \.offset) { _, completion in
                        Button {
                            Task { await selectCompletion(completion) }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(completion.title)
                                    .foregroundStyle(.primary)
                                if !completion.subtitle.isEmpty {
                                    Text(completion.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                if let searchError {
                    Section {
                        Text(searchError)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("Add Destination")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func selectCompletion(_ completion: MKLocalSearchCompletion) async {
        isResolving = true
        searchError = nil
        defer { isResolving = false }

        do {
            let place = try await searchService.resolve(completion)
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedName = trimmedName.isEmpty ? place.title : trimmedName
            settings.savedLocations.add(name: resolvedName, place: place)
            dismiss()
        } catch {
            searchError = error.localizedDescription
        }
    }
}

private struct PastRoutesSettingsView: View {
    @ObservedObject var locationManager: LocationManager
    let distancePreferences: DistanceUnitPreferences

    var body: some View {
        Group {
            if locationManager.drivenPathSummaries.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "road.lanes.curved.left")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No past routes")
                        .font(.headline)
                    Text("Roads you drive are saved here. Deleting a route lets War Map treat those roads as new again.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(locationManager.drivenPathSummaries) { route in
                        Button {
                            if locationManager.highlightedSegmentIndex == route.id {
                                locationManager.setHighlightedSegment(nil)
                            } else {
                                locationManager.setHighlightedSegment(route.id)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(route.title)
                                    Text(route.detail(preferences: distancePreferences))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if locationManager.highlightedSegmentIndex == route.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.yellow)
                                }
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                locationManager.deleteDrivenSegment(at: route.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Past Routes")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            locationManager.setHighlightedSegment(nil)
        }
    }
}
