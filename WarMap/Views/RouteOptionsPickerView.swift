import MapKit
import SwiftUI

struct RouteOptionsPickerView: View {
    let options: [RouteOption]
    let selectedID: String?
    let distancePreferences: DistanceUnitPreferences
    let onSelect: (RouteOption) -> Void

    private var baselineOption: RouteOption? {
        options.min { lhs, rhs in
            if lhs.route.expectedTravelTime != rhs.route.expectedTravelTime {
                return lhs.route.expectedTravelTime < rhs.route.expectedTravelTime
            }
            return lhs.route.distance < rhs.route.distance
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Routes")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            HStack(spacing: 8) {
                ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                    let baseline = baselineOption?.route
                    let isBaseline = option.id == baselineOption?.id
                    let title = baseline.map {
                        option.shortTitle(relativeTo: $0, preferences: distancePreferences, isBaseline: isBaseline)
                    } ?? "Route"
                    Button {
                        onSelect(option)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(selectedID == option.id ? Color.accentColor : .primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.9)

                            Text(option.detailLabel(preferences: distancePreferences))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(selectedID == option.id ? Color.accentColor.opacity(0.14) : Color(.secondarySystemFill))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(
                                    selectedID == option.id ? Color.accentColor : Color.clear,
                                    lineWidth: 2
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(
                        "Route \(index + 1), \(title), \(option.detailLabel(preferences: distancePreferences))"
                    )
                    .accessibilityAddTraits(selectedID == option.id ? .isSelected : [])
                }
            }
            .frame(minHeight: 72)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
    }
}
