import Foundation
import UserNotifications

@MainActor
class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    @Published var isPermissionGranted = false

    private init() {}

    func requestPermission() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
            isPermissionGranted = granted
        } catch {
            print("Notification permission failed: \(error.localizedDescription)")
        }
    }

    /// "You're already behind" notification when a league rival has lower screen time
    func scheduleLeagueAlert(rivalName: String, achievement: String) {
        let content = UNMutableNotificationContent()
        content.title = "You're already behind."
        content.body = "\(rivalName) \(achievement)"
        content.sound = .default
        content.categoryIdentifier = "LEAGUE_ALERT"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request)
    }

    /// Daily summary notification
    func scheduleDailySummary(screenTime: String, rank: Int, leagueName: String) {
        let content = UNMutableNotificationContent()
        content.title = "Daily Recap"
        content.body = "You used \(screenTime) today. You're #\(rank) in \(leagueName)."
        content.sound = .default

        var dateComponents = DateComponents()
        dateComponents.hour = 21
        dateComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(
            identifier: "daily_summary",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request)
    }

    /// Streak reminder
    func scheduleStreakReminder(currentStreak: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Keep your streak alive! 🔥"
        content.body = "You're on a \(currentStreak)-day streak. Stay under your goal today."
        content.sound = .default

        var dateComponents = DateComponents()
        dateComponents.hour = 9
        dateComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(
            identifier: "streak_reminder",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request)
    }

    func registerNotificationCategories() {
        let checkAction = UNNotificationAction(
            identifier: "CHECK_LEAGUE",
            title: "Check League Standing",
            options: .foreground
        )
        let ignoreAction = UNNotificationAction(
            identifier: "IGNORE",
            title: "Ignore.",
            options: .destructive
        )

        let leagueCategory = UNNotificationCategory(
            identifier: "LEAGUE_ALERT",
            actions: [checkAction, ignoreAction],
            intentIdentifiers: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([leagueCategory])
    }
}
