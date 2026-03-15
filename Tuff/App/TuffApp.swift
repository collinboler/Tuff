import SwiftUI
import FirebaseCore
import FirebaseAuth
import FamilyControls

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()
        // Register for remote notifications so Firebase can get the APNs token
        // needed for phone auth (silent push verification)
        application.registerForRemoteNotifications()
        return true
    }

    // Forward APNs device token to Firebase Auth
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Auth.auth().setAPNSToken(deviceToken, type: .unknown)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("APNs registration failed: \(error)")
    }

    // Let Firebase Auth intercept its silent push notifications
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        if Auth.auth().canHandleNotification(userInfo) {
            completionHandler(.noData)
            return
        }
        completionHandler(.noData)
    }
}

@main
struct TuffApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var screenTimeManager = ScreenTimeManager.shared
    @StateObject private var notificationManager = NotificationManager.shared
    @StateObject private var auth = AuthViewModel()

    var body: some Scene {
        WindowGroup {
            if auth.isSignedIn {
                ContentView()
                    .environmentObject(screenTimeManager)
                    .environmentObject(notificationManager)
                    .environmentObject(auth)
                    .task {
                        await screenTimeManager.requestAuthorization()
                        await notificationManager.requestPermission()
                        notificationManager.registerNotificationCategories()
                        screenTimeManager.startMonitoring()
                    }
            } else {
                PhoneSignInView()
                    .environmentObject(auth)
            }
        }
    }
}
