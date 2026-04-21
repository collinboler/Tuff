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

    /// Fires when a league the user is in crosses its end date. Separate
    /// notifications for "you won" vs "you owe" so the body reads correctly.
    func scheduleLeagueEndedNotification(leagueId: String,
                                         leagueName: String,
                                         winnerName: String,
                                         userWon: Bool,
                                         netOutcomeCents: Int) {
        let content = UNMutableNotificationContent()
        let dollars = String(format: "$%.2f", Double(abs(netOutcomeCents)) / 100.0)
        if userWon {
            content.title = "You won \(leagueName)!"
            content.body = "Lowest spent takes the pool — you earn \(dollars)."
        } else if netOutcomeCents == 0 {
            content.title = "\(leagueName) has ended"
            content.body = "\(winnerName) won. You didn't spend anything — nothing owed."
        } else {
            content.title = "\(leagueName) has ended"
            content.body = "\(winnerName) won the pool. You owe \(dollars)."
        }
        content.sound = .default
        content.categoryIdentifier = "LEAGUE_ENDED"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        // Stable identifier per-league prevents duplicate notifications
        // if detection runs twice in quick succession.
        let request = UNNotificationRequest(
            identifier: "league_ended_\(leagueId)",
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
