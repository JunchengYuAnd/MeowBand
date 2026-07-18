import SwiftUI

@main
struct MeowBandApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .persistentSystemOverlays(.hidden)
                .statusBarHidden(true)
        }
    }
}
