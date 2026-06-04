import SwiftUI

struct ContentView: View {
    var body: some View {
        ZStack {
            Color(.systemBackground)
            VStack(spacing: 12) {
                Image(systemName: "map")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("War Map")
                    .font(.title2.weight(.semibold))
                Text("v0.0.1")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("Placeholder build")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

#Preview {
    ContentView()
}
