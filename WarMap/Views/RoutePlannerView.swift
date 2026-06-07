import MapKit
import SwiftUI

struct RoutePlannerView: View {
    @StateObject private var viewModel: RoutePlannerViewModel
    @State private var showSettings = false
    @State private var showSavedDestinations = false
    @FocusState private var focusedField: RouteField?

    private let chromeButtonSize: CGFloat = 44
    private let searchRowHeight: CGFloat = 44

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
                if viewModel.isSearchPanelExpanded {
                    expandedSearchChrome
                        .transition(.move(edge: .top).combined(with: .opacity))
                } else {
                    collapsedSearchChrome
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if let error = viewModel.searchError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 64)
                        .padding(.top, 8)
                }

                Spacer(minLength: 0)
                    .allowsHitTesting(false)
            }
            .allowsHitTesting(true)

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
                    if !viewModel.routeOptions.isEmpty, !viewModel.isNavigating {
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

    private func mapChromeButton(
        systemName: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: chromeButtonSize, height: chromeButtonSize)
                .background(.regularMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private func clearFieldButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Clear")
    }

    private func searchRowActionButton(
        systemName: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.medium))
                .foregroundStyle(tint)
                .frame(width: chromeButtonSize, height: searchRowHeight)
        }
        .buttonStyle(.plain)
    }

    private var collapsedSearchChrome: some View {
        HStack(alignment: .center, spacing: 8) {
            mapChromeButton(
                systemName: "gearshape.fill",
                accessibilityLabel: "Settings"
            ) {
                showSettings = true
            }

            collapsedSearchBar
                .frame(maxWidth: .infinity)

            compassSpacer
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    private var expandedSearchChrome: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(spacing: 0) {
                Color.clear.frame(height: 10)
                mapChromeButton(
                    systemName: "gearshape.fill",
                    accessibilityLabel: "Settings"
                ) {
                    showSettings = true
                }
                .frame(height: searchRowHeight)
                Divider().frame(height: 1)
                mapChromeButton(
                    systemName: "mappin.and.ellipse",
                    accessibilityLabel: "Saved destinations"
                ) {
                    showSavedDestinations = true
                }
                .frame(height: searchRowHeight)
                Color.clear.frame(height: 10)
            }

            expandedSearchCard
                .frame(maxWidth: .infinity)

            VStack(spacing: 0) {
                Color.clear.frame(height: 10)
                compassSpacer
                    .frame(height: searchRowHeight)
                Divider().frame(height: 1)
                Color.clear
                    .frame(width: chromeButtonSize, height: searchRowHeight)
                    .accessibilityHidden(true)
                Color.clear.frame(height: 10)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    private var compassSpacer: some View {
        Color.clear
            .frame(width: chromeButtonSize, height: chromeButtonSize)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
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
            HStack(alignment: .center, spacing: 10) {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 10, height: 10)
                VStack(spacing: 0) {
                    HStack(spacing: 6) {
                        startFieldBlock
                        if viewModel.canClearStart {
                            clearFieldButton(action: viewModel.clearStart)
                        }
                    }
                    .frame(height: searchRowHeight)
                    if viewModel.focusedField == .start, !viewModel.searchCompletions.isEmpty {
                        suggestionsScroll
                    }
                }
                searchRowActionButton(
                    systemName: "location.fill",
                    tint: viewModel.startUsesCurrentLocation ? .blue : .secondary,
                    action: viewModel.useCurrentLocationForStart
                )
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            Divider().padding(.leading, 22)

            HStack(alignment: .center, spacing: 10) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 10, height: 10)
                VStack(spacing: 0) {
                    HStack(spacing: 6) {
                        destinationFieldBlock
                        if viewModel.canClearDestination {
                            clearFieldButton(action: viewModel.clearDestination)
                        }
                    }
                    .frame(height: searchRowHeight)
                    if viewModel.focusedField == .destination, !viewModel.searchCompletions.isEmpty {
                        suggestionsScroll
                    }
                }
                searchRowActionButton(
                    systemName: "arrow.up.arrow.down",
                    tint: .secondary,
                    action: viewModel.swapEndpoints
                )
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
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
        .frame(maxWidth: .infinity, minHeight: searchRowHeight, alignment: .leading)
    }

    private var destinationFieldBlock: some View {
        TextField("Where to?", text: $viewModel.destinationQuery)
            .textInputAutocapitalization(.words)
            .disableAutocorrection(true)
            .focused($focusedField, equals: .destination)
            .onChange(of: viewModel.destinationQuery) { _ in
                viewModel.handleDestinationQueryChange()
            }
            .frame(maxWidth: .infinity, minHeight: searchRowHeight, alignment: .leading)
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
