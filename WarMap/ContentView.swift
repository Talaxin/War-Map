import SwiftUI

struct ContentView: View {
    @StateObject private var settings = AppSettings()

    var body: some View {
        RoutePlannerView(settings: settings)
    }
}

#Preview {
    ContentView()
}
