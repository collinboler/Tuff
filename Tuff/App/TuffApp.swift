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
        #if DEBUG
        Auth.auth().setAPNSToken(deviceToken, type: .sandbox)
        #else
        Auth.auth().setAPNSToken(deviceToken, type: .prod)
        #endif
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

    // Handle reCAPTCHA callback URL so Firebase phone auth can complete
    func application(_ app: UIApplication, open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        return Auth.auth().canHandle(url)
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
            Group {
                if !auth.isSignedIn {
                    PhoneSignInView()
                } else if auth.needsOnboarding {
                    OnboardingView()
                } else {
                    ContentView()
                        .onAppear {
                            screenTimeManager.startMonitoring()
                        }
                }
            }
            .environmentObject(auth)
            .environmentObject(screenTimeManager)
            .environmentObject(notificationManager)
        }
    }
}
