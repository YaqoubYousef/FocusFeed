import BackgroundTasks
import Foundation
import UIKit
import UserNotifications
import WebKit

/// Checks the Instagram DM inbox in the background and posts local notifications for new messages.
///
/// - iOS decides when the background check runs (usually every 15 minutes to a few hours,
///   more often if you open the app regularly). It does not run after you swipe the app away.
/// - It uses your existing Instagram login (cookies copied from the web view).
enum InboxChecker {
    static let taskID = "com.focusfeed.app.inbox-refresh"

    private static let lastTimestampKey = "ff.lastMessageTimestamp"
    private static let userAgentKey = "ff.userAgent"
    private static let instagramWebAppID = "936619743392459"
    private static let fallbackUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    // MARK: Scheduling

    static func scheduleNext() {
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    static func clearBadge() {
        UNUserNotificationCenter.current().setBadgeCount(0, withCompletionHandler: nil)
    }

    /// When you leave the app, everything currently in the inbox counts as seen.
    @MainActor
    static func markEverythingSeen() {
        let app = UIApplication.shared
        var bgTask = UIBackgroundTaskIdentifier.invalid
        bgTask = app.beginBackgroundTask { app.endBackgroundTask(bgTask) }
        syncCookies {
            Task { @MainActor in
                await check(notify: false)
                app.endBackgroundTask(bgTask)
            }
        }
    }

    // MARK: Login cookies & user agent (copied from the web view)

    /// Must be called on the main thread.
    static func syncCookies(completion: (() -> Void)? = nil) {
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
            for cookie in cookies where cookie.domain.hasSuffix("instagram.com") {
                HTTPCookieStorage.shared.setCookie(cookie)
            }
            completion?()
        }
    }

    static func saveUserAgent(_ userAgent: String) {
        UserDefaults.standard.set(userAgent, forKey: userAgentKey)
    }

    // MARK: Inbox check

    static func check(notify: Bool) async {
        let base = URL(string: "https://www.instagram.com/")!
        let cookies = HTTPCookieStorage.shared.cookies(for: base) ?? []
        guard cookies.contains(where: { $0.name == "sessionid" }),
              let viewerID = cookies.first(where: { $0.name == "ds_user_id" })?.value
        else { return }   // not logged in yet
        let csrf = cookies.first(where: { $0.name == "csrftoken" })?.value ?? ""

        var components = URLComponents(string: "https://www.instagram.com/api/v1/direct_v2/inbox/")!
        components.queryItems = [
            URLQueryItem(name: "persistentBadging", value: "true"),
            URLQueryItem(name: "limit", value: "20"),
            URLQueryItem(name: "thread_message_limit", value: "1"),
        ]
        var request = URLRequest(url: components.url!, timeoutInterval: 20)
        request.setValue(instagramWebAppID, forHTTPHeaderField: "X-IG-App-ID")
        request.setValue(csrf, forHTTPHeaderField: "X-CSRFToken")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue("https://www.instagram.com/direct/inbox/", forHTTPHeaderField: "Referer")
        request.setValue(UserDefaults.standard.string(forKey: userAgentKey) ?? fallbackUserAgent,
                         forHTTPHeaderField: "User-Agent")

        guard let result = try? await URLSession.shared.data(for: request),
              (result.1 as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: result.0) as? [String: Any],
              let inbox = json["inbox"] as? [String: Any]
        else { return }

        let threads = inbox["threads"] as? [[String: Any]] ?? []
        let defaults = UserDefaults.standard
        let lastSeen = defaults.object(forKey: lastTimestampKey) as? Double
        var newest = lastSeen ?? 0
        var fresh: [(thread: [String: Any], item: [String: Any])] = []

        for thread in threads {
            guard let item = (thread["items"] as? [[String: Any]])?.first else { continue }
            let ts = number(item["timestamp"])
            newest = max(newest, ts)
            guard let lastSeen = lastSeen, ts > lastSeen else { continue }   // first run: just remember
            if string(item["user_id"]) == viewerID { continue }              // you sent it
            if seenElsewhere(thread, viewerID: viewerID, timestamp: ts) { continue }
            fresh.append((thread, item))
        }
        defaults.set(newest, forKey: lastTimestampKey)

        guard notify else { return }
        for message in fresh.prefix(5) {
            await post(thread: message.thread, item: message.item)
        }
        if let unseen = inbox["unseen_count"] {
            UNUserNotificationCenter.current().setBadgeCount(Int(number(unseen)), withCompletionHandler: nil)
        }
    }

    // MARK: Notifications

    private static func post(thread: [String: Any], item: [String: Any]) async {
        let users = thread["users"] as? [[String: Any]] ?? []
        let sender = users.first { string($0["pk"]) == string(item["user_id"]) }
        let senderName = nonEmpty(string(sender?["full_name"])) ?? nonEmpty(string(sender?["username"]))
        let threadTitle = nonEmpty(string(thread["thread_title"]))
        let isGroup = (thread["is_group"] as? Bool) ?? false
        let text = describe(item)

        let content = UNMutableNotificationContent()
        if isGroup {
            content.title = threadTitle ?? "Group chat"
            content.body = senderName.map { "\($0): \(text)" } ?? text
        } else {
            content.title = senderName ?? threadTitle ?? "Instagram"
            content.body = text
        }
        content.sound = .default

        let threadID = nonEmpty(string(thread["thread_v2_id"])) ?? nonEmpty(string(thread["thread_id"]))
        content.threadIdentifier = threadID ?? "inbox"
        content.userInfo = ["url": threadID.map { "https://www.instagram.com/direct/t/\($0)/" }
                                    ?? "https://www.instagram.com/direct/inbox/"]

        let id = nonEmpty(string(item["item_id"])) ?? UUID().uuidString
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    private static func describe(_ item: [String: Any]) -> String {
        switch string(item["item_type"]) {
        case "text":
            return nonEmpty(string(item["text"])) ?? "New message"
        case "clip":
            return "Sent a reel"
        case "media_share", "xma_media_share", "generic_xma":
            return "Sent a post"
        case "media", "raven_media", "visual_media":
            return "Sent a photo or video"
        case "voice_media":
            return "Sent a voice message"
        case "animated_media":
            return "Sent a GIF"
        case "like":
            return "❤️"
        case "reel_share", "story_share":
            return "Replied to or shared a story"
        case "link":
            let link = item["link"] as? [String: Any]
            return nonEmpty(string(link?["text"])) ?? "Sent a link"
        default:
            return "New message"
        }
    }

    // MARK: Helpers

    private static func seenElsewhere(_ thread: [String: Any], viewerID: String, timestamp: Double) -> Bool {
        guard let seen = thread["last_seen_at"] as? [String: Any],
              let mine = seen[viewerID] as? [String: Any] else { return false }
        return number(mine["timestamp"]) >= timestamp
    }

    private static func number(_ value: Any?) -> Double {
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s) ?? 0 }
        return 0
    }

    private static func string(_ value: Any?) -> String? {
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        return nil
    }

    private static func nonEmpty(_ s: String?) -> String? {
        guard let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }
}
