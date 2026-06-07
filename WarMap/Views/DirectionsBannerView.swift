import SwiftUI

struct DirectionsBannerView: View {
    let guidance: NavigationGuidanceState
    let distancePreferences: DistanceUnitPreferences
    let isNavigating: Bool
    let isCalculatingRoute: Bool
    let hasRoute: Bool
    let onStart: () -> Void
    let onStop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isCalculatingRoute {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Calculating route…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if hasRoute {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: isNavigating ? "location.north.line.fill" : "car.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)
                        .rotationEffect(isNavigating ? .degrees(0) : .degrees(0))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(guidance.instruction.isEmpty ? "Follow the route" : guidance.instruction)
                            .font(.headline)
                            .lineLimit(2)

                        HStack(spacing: 12) {
                            if !guidance.arrived {
                                Text(DistanceFormatting.format(
                                    distance: guidance.distanceToManeuver,
                                    preferences: distancePreferences
                                ))
                                    .font(.subheadline.weight(.semibold))
                            }
                            Text(DistanceFormatting.format(
                                distance: guidance.remainingDistance,
                                preferences: distancePreferences
                            ))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(DistanceFormatting.format(duration: guidance.remainingTime))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if isNavigating {
                    Button("End", role: .destructive, action: onStop)
                        .buttonStyle(.bordered)
                } else {
                    Button(action: onStart) {
                        Text("Go")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 12, y: -2)
    }
}
