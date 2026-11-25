import SwiftUI

@main
struct FocusFeedApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            InstagramWebView(startURL: URL(string: "https://www.instagram.com/")!)
        }
    }
}
