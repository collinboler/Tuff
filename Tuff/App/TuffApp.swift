import SwiftUI
import FirebaseCore
import FamilyControls

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()
        return true
    }
}

@main
struct TuffApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
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
