import MapKit
import SwiftUI

struct SavedDestinationsMenuView: View {
    @ObservedObject var settings: AppSettings
    let currentDestination: MapPlace?
    let onSelect: (SavedLocation) -> Void
    let onSaveCurrent: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var showAddLocation = false
    @State private var showSaveCurrent = false
    @State private var saveCurrentName = ""

    var body: some View {
        NavigationStack {
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
                                dismiss()
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
            .navigationTitle("Destinations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
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
                AddSavedDestinationView(settings: settings)
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
    }
}

private struct AddSavedDestinationView: View {
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
