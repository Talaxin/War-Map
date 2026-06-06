import SwiftUI

struct RouteOptionsPickerView: View {
    let options: [RouteOption]
    let selectedID: String?
    let onSelect: (RouteOption) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Routes")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            HStack(spacing: 8) {
                ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                    Button {
                        onSelect(option)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(option.additionalTimeLabel)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(selectedID == option.id ? Color.accentColor : .primary)

                            Text(option.detailLabel)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
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
                    .accessibilityLabel("Route \(index + 1), \(option.additionalTimeLabel), \(option.detailLabel)")
                    .accessibilityAddTraits(selectedID == option.id ? .isSelected : [])
                }
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
    }
}
