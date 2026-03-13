import SwiftUI
import FamilyControls

@main
struct TuffApp: App {
    @StateObject private var screenTimeManager = ScreenTimeManager.shared
    @StateObject private var notificationManager = NotificationManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(screenTimeManager)
                .environmentObject(notificationManager)
                .task {
                    await screenTimeManager.requestAuthorization()
                    await notificationManager.requestPermission()
                    notificationManager.registerNotificationCategories()
                    screenTimeManager.startMonitoring()
                }
        }
    }
}
