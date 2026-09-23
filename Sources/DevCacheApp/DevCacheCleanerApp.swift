import SwiftUI

@main
struct DevCacheCleanerApp: App {
    @StateObject private var viewModel = CacheViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
        }
        .defaultSize(width: 1280, height: 820)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
    }
}
