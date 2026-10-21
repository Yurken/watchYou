import SwiftUI

@main
struct WatchYouWatchApp: App {
    @StateObject private var model = WatchAppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
        }
    }
}
