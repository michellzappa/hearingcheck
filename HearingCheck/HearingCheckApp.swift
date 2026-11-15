import SwiftUI

@main
struct HearingCheckApp: App {
    @State private var audio = AudioController()
    @State private var store = SessionStore()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(audio)
                .environment(store)
        }
    }
}
