import MapKit
import SwiftUI

struct RoutePlannerView: View {
    @StateObject private var viewModel: RoutePlannerViewModel
    @State private var showSettings = false
    @State private var showSavedDestinations = false
    @FocusState private var focusedField: RouteField?

    init(settings: AppSettings) {
        _viewModel = StateObject(wrappedValue: RoutePlannerViewModel(settings: settings))
    }

    var body: some View {
        ZStack(alignment: .top) {
            MapCanvasView(
                region: viewModel.mapRegion,
                route: viewModel.route,
                trackedPolylines: viewModel.locationManager.trackedPolylines,
                start: viewModel.startPlace,
                destination: viewModel.destinationPlace,
                showsStartPin: !viewModel.startUsesCurrentLocation,
                isNavigating: viewModel.isNavigating,
                followUser: viewModel.followUserOnMap,
                trackingMode: viewModel.mapTrackingMode,
                routeColor: viewModel.routeUIColor,
                trackedColor: viewModel.trackedUIColor,
                highlightedTrackSegmentIndex: viewModel.locationManager.highlightedSegmentIndex,
                vehicleType: viewModel.settings.vehicleType,
                trackedPathRevision: viewModel.locationManager.trackedPathRevision,
                northResetRevision: viewModel.northResetRevision,
                userCenterRevision: viewModel.userCenterRevision,
                onUserInteraction: viewModel.userDidInteractWithMap
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(spacing: 8) {
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.title3)
                                .foregroundStyle(.primary)
                                .padding(10)
                                .background(.regularMaterial, in: Circle())
                        }
                        .accessibilityLabel("Settings")

                        Button {
                            showSavedDestinations = true
                        } label: {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.title3)
                                .foregroundStyle(.primary)
                                .padding(10)
                                .background(.regularMaterial, in: Circle())
                        }
                        .accessibilityLabel("Saved destinations")
                    }

                    Group {
                        if viewModel.isSearchPanelExpanded {
                            expandedSearchCard
                                .transition(.move(edge: .top).combined(with: .opacity))
                        } else {
                            collapsedSearchBar
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .frame(maxWidth: .infinity)

                    // Compass aligned with settings gear (replaces built-in map compass).
                    Button(action: viewModel.resetMapNorth) {
                        Image(systemName: "location.north.fill")
                            .font(.title3)
                            .foregroundStyle(.primary)
                            .padding(10)
                            .background(.regularMaterial, in: Circle())
                    }
                    .accessibilityLabel("Reset map to north")
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)

                if let error = viewModel.searchError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 64)
                        .padding(.top, 8)
                }

                Spacer(minLength: 0)
            }

            if viewModel.locationManager.isAuthorized {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: viewModel.recenterOnUser) {
                            Image(systemName: viewModel.centerButtonSymbolName)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(viewModel.followUserOnMap ? .white : Color.accentColor)
                                .frame(width: 48, height: 48)
                                .background(
                                    viewModel.followUserOnMap ? Color.accentColor : Color(.systemBackground),
                                    in: Circle()
                                )
                                .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
                        }
                        .accessibilityLabel(viewModel.centerButtonAccessibilityLabel)
                        .padding(.trailing, 16)
                        .padding(.bottom, 8)
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.isSearchPanelExpanded)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if viewModel.hasRoute || viewModel.isCalculatingRoute {
                VStack(spacing: 8) {
                    if viewModel.routeOptions.count > 1, !viewModel.isNavigating {
                        RouteOptionsPickerView(
                            options: viewModel.routeOptions,
                            selectedID: viewModel.selectedRouteOptionID,
                            distancePreferences: viewModel.settings.distanceUnitPreferences,
                            onSelect: viewModel.selectRouteOption
                        )
                    }

                    DirectionsBannerView(
                        guidance: viewModel.guidance,
                        distancePreferences: viewModel.settings.distanceUnitPreferences,
                        isNavigating: viewModel.isNavigating,
                        isCalculatingRoute: viewModel.isCalculatingRoute,
                        hasRoute: viewModel.hasRoute,
                        onStart: viewModel.startNavigation,
                        onStop: viewModel.stopNavigation
                    )
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(
                settings: viewModel.settings,
                locationManager: viewModel.locationManager
            )
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showSavedDestinations) {
            SavedDestinationsMenuView(
                settings: viewModel.settings,
                currentDestination: viewModel.currentDestinationForSaving,
                onSelect: viewModel.setDestination(from:),
                onSaveCurrent: viewModel.saveCurrentDestination(as:)
            )
            .presentationDetents([.medium, .large])
        }
        .onAppear { viewModel.onAppear() }
        .onReceive(viewModel.locationManager.$currentLocation) { _ in
            viewModel.handleLocationUpdate()
        }
        .onReceive(viewModel.locationManager.$authorizationStatus) { _ in
            viewModel.handleAuthorizationChange()
        }
        .onChange(of: focusedField) { newValue in
            viewModel.focusedField = newValue
            if newValue == nil {
                viewModel.blurSearch()
            } else if let newValue {
                viewModel.focus(newValue)
            }
        }
        .onChange(of: viewModel.focusedField) { newValue in
            focusedField = newValue
        }
        .onChange(of: viewModel.locationManager.highlightedSegmentIndex) { index in
            if index != nil {
                viewModel.userDidInteractWithMap()
            }
        }
    }

    private func clearFieldButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Clear")
    }

    private var collapsedSearchBar: some View {
        Button(action: viewModel.expandSearchPanel) {
            HStack(spacing: 10) {
                Image(systemName: "mappin.and.ellipse")
                    .foregroundStyle(.secondary)
                Text(viewModel.collapsedSummary)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
    }

    private var expandedSearchCard: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 10, height: 10)
                    .padding(.top, 6)
                VStack(spacing: 0) {
                    HStack(spacing: 6) {
                        startFieldBlock
                        if viewModel.canClearStart {
                            clearFieldButton(action: viewModel.clearStart)
                        }
                    }
                    if viewModel.focusedField == .start, !viewModel.searchCompletions.isEmpty {
                        suggestionsScroll
                    }
                }
                Button(action: viewModel.useCurrentLocationForStart) {
                    Image(systemName: "location.fill")
                        .font(.body)
                        .foregroundStyle(viewModel.startUsesCurrentLocation ? .blue : .secondary)
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            Divider().padding(.leading, 32)

            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 10, height: 10)
                    .padding(.top, 6)
                VStack(spacing: 0) {
                    HStack(spacing: 6) {
                        destinationFieldBlock
                        if viewModel.canClearDestination {
                            clearFieldButton(action: viewModel.clearDestination)
                        }
                    }
                    if viewModel.focusedField == .destination, !viewModel.searchCompletions.isEmpty {
                        suggestionsScroll
                    }
                }
                Button(action: viewModel.swapEndpoints) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }

    @ViewBuilder
    private var startFieldBlock: some View {
        Group {
            if viewModel.startUsesCurrentLocation && focusedField != .start {
                Text(viewModel.startDisplayText)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onTapGesture { focusedField = .start }
            } else {
                TextField("Choose starting point", text: $viewModel.startQuery)
                    .textInputAutocapitalization(.words)
                    .disableAutocorrection(true)
                    .focused($focusedField, equals: .start)
                    .onChange(of: viewModel.startQuery) { _ in
                        viewModel.handleStartQueryChange()
                    }
            }
        }
        .frame(minHeight: 28)
    }

    private var destinationFieldBlock: some View {
        TextField("Where to?", text: $viewModel.destinationQuery)
            .textInputAutocapitalization(.words)
            .disableAutocorrection(true)
            .focused($focusedField, equals: .destination)
            .onChange(of: viewModel.destinationQuery) { _ in
                viewModel.handleDestinationQueryChange()
            }
            .frame(minHeight: 28)
    }

    private var suggestionsScroll: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(viewModel.searchCompletions.enumerated()), id: \.offset) { _, completion in
                    Button {
                        Task { await viewModel.selectCompletion(completion) }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(completion.title)
                                .font(.body)
                                .foregroundStyle(.primary)
                            if !completion.subtitle.isEmpty {
                                Text(completion.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 8)
                    }
                    if completion.title != viewModel.searchCompletions.last?.title {
                        Divider()
                    }
                }
            }
        }
        .frame(maxHeight: 180)
        .padding(.top, 4)
    }
}

#Preview {
    RoutePlannerView(settings: AppSettings())
}
