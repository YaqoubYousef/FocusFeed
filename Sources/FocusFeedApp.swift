import SwiftUI
import UserNotifications

@main
struct FocusFeedApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        // iOS wakes the app now and then to check for new DMs.
        .backgroundTask(.appRefresh(InboxChecker.taskID)) {
            InboxChecker.scheduleNext()
            await InboxChecker.check(notify: true)
        }
    }
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            InstagramWebView(startURL: URL(string: "https://www.instagram.com/")!)
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                InboxChecker.clearBadge()
            case .background:
                InboxChecker.scheduleNext()
                InboxChecker.markEverythingSeen()
            default:
                break
            }
        }
    }
}

/// Opening a conversation when a notification is tapped.
enum DeepLink {
    static var pending: URL?
    static let didRequestOpen = Notification.Name("FocusFeedOpenURL")

    static func open(_ url: URL) {
        pending = url
        NotificationCenter.default.post(name: didRequestOpen, object: nil)
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        return true
    }

    // The app is open: no banners, you're already looking at Instagram.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([])
    }

    // Tapped a notification: open that conversation.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let link = response.notification.request.content.userInfo["url"] as? String,
           let url = URL(string: link) {
            DeepLink.open(url)
        }
        completionHandler()
    }
}
