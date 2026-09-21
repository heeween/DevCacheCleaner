import SwiftUI

@main
struct DevCacheCleanerApp: App {
    @StateObject private var viewModel = CacheViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
        }
        .windowToolbarStyle(.unified)
    }
}
