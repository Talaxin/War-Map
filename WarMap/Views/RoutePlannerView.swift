import MapKit
import SwiftUI

struct RoutePlannerView: View {
    @StateObject private var viewModel = RoutePlannerViewModel()

    var body: some View {
        ZStack(alignment: .top) {
            MapCanvasView(
                region: viewModel.mapRegion,
                route: viewModel.route,
                start: viewModel.startPlace,
                destination: viewModel.destinationPlace,
                isNavigating: viewModel.isNavigating,
                followUser: viewModel.followUserOnMap
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                searchCard
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                if viewModel.focusedField != nil, !viewModel.searchCompletions.isEmpty {
                    suggestionsList
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                }

                if let error = viewModel.searchError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }

                Spacer(minLength: 0)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if viewModel.hasRoute || viewModel.isCalculatingRoute {
                DirectionsBannerView(
                    guidance: viewModel.guidance,
                    isNavigating: viewModel.isNavigating,
                    isCalculatingRoute: viewModel.isCalculatingRoute,
                    hasRoute: viewModel.hasRoute,
                    onStart: viewModel.startNavigation,
                    onStop: viewModel.stopNavigation
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
        .onAppear { viewModel.onAppear() }
        .onReceive(viewModel.locationManager.$currentLocation) { _ in
            viewModel.handleLocationUpdate()
        }
    }

    private var searchCard: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 10, height: 10)
                startRow
                Button(action: viewModel.swapEndpoints) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Swap start and destination")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider().padding(.leading, 32)

            HStack(alignment: .center, spacing: 10) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 10, height: 10)
                destinationRow
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }

    @ViewBuilder
    private var startRow: some View {
        HStack(spacing: 8) {
            Group {
                if viewModel.startUsesCurrentLocation && viewModel.focusedField != .start {
                    Text(viewModel.startDisplayText)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onTapGesture { viewModel.focus(.start) }
                } else {
                    TextField("Choose starting point", text: $viewModel.startQuery)
                        .textInputAutocapitalization(.words)
                        .disableAutocorrection(true)
                        .onChange(of: viewModel.startQuery) { _ in
                            viewModel.handleStartQueryChange()
                        }
                        .onTapGesture { viewModel.focus(.start) }
                }
            }

            Button(action: viewModel.useCurrentLocationForStart) {
                Image(systemName: "location.fill")
                    .font(.body)
                    .foregroundStyle(viewModel.startUsesCurrentLocation ? .blue : .secondary)
            }
            .accessibilityLabel("Use current location")
        }
        .onSubmit { viewModel.blurSearch() }
    }

    private var destinationRow: some View {
        TextField("Where to?", text: $viewModel.destinationQuery)
            .textInputAutocapitalization(.words)
            .disableAutocorrection(true)
            .onChange(of: viewModel.destinationQuery) { _ in
                viewModel.handleDestinationQueryChange()
            }
            .onTapGesture { viewModel.focus(.destination) }
            .onSubmit { viewModel.blurSearch() }
    }

    private var suggestionsList: some View {
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
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                if completion.title != viewModel.searchCompletions.last?.title {
                    Divider().padding(.leading, 14)
                }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.1), radius: 8, y: 3)
        .overlay {
            if viewModel.isResolvingSearch {
                ProgressView()
                    .padding()
            }
        }
    }
}

#Preview {
    RoutePlannerView()
}
