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
    @State private var pageColor = Color("LaunchBackground")
    @State private var showSplash = true

    var body: some View {
        ZStack {
            pageColor.ignoresSafeArea()

            InstagramWebView(
                startURL: URL(string: "https://www.instagram.com/")!,
                onBackgroundColor: { color in
                    withAnimation(.easeInOut(duration: 0.2)) { pageColor = Color(color) }
                },
                onFirstLoad: {
                    withAnimation(.easeOut(duration: 0.35)) { showSplash = false }
                }
            )

            // Same look as the launch screen, then fades into Instagram (no white flash).
            if showSplash {
                ZStack {
                    Color("LaunchBackground").ignoresSafeArea()
                    Image("LaunchLogo")
                        .resizable()
                        .frame(width: 96, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .transition(.opacity)
            }
        }
    }
}
