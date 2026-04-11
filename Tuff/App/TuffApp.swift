import SwiftUI
import FirebaseCore
import FirebaseAuth
import UserNotifications

// MARK: - Permissions gate (shown when screen time not yet authorized after login)

struct PermissionsGateView: View {
    @EnvironmentObject private var screenTimeManager: ScreenTimeManager
    @EnvironmentObject private var notificationManager: NotificationManager
    @State private var isRequesting = false

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            VStack(spacing: 28) {
                Spacer()

                Image(systemName: "hourglass.circle.fill")
                    .font(.system(size: 64))
                    .foregroundColor(TuffColors.accent)

                VStack(spacing: 8) {
                    Text("SCREEN TIME NEEDED")
                        .font(.system(size: 26, weight: .black, design: .default).width(.condensed))
                        .foregroundColor(.black)
                        .tracking(1)
                    Text("Tuff needs Screen Time access to track your usage and compete in leagues.")
                        .font(.system(size: 15))
                        .foregroundColor(TuffColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        isRequesting = true
                        Task {
                            await screenTimeManager.requestAuthorization()
                            await notificationManager.requestPermission()
                            isRequesting = false
                        }
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(TuffColors.accent)
                                .frame(height: 54)
                            if isRequesting {
                                ProgressView().tint(.black)
                            } else {
                                Text("Allow Screen Time")
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(.black)
                            }
                        }
                    }
                    .disabled(isRequesting)

                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(TuffColors.textSecondary)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
            }
        }
        .colorScheme(.light)
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()
        // Register for remote notifications so Firebase can get the APNs token
        // needed for phone auth (silent push verification)
        application.registerForRemoteNotifications()

        // Cap URLSession HTTP cache so downloaded images don't bloat disk/memory.
        // RemoteImageCache (NSCache) handles the in-memory layer separately.
        URLCache.shared = URLCache(
            memoryCapacity: 10 * 1024 * 1024,  //  10 MB memory
            diskCapacity:   50 * 1024 * 1024,  //  50 MB disk
            diskPath: "tuff_url_cache"
        )
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
                } else if !screenTimeManager.isAuthorized {
                    PermissionsGateView()
                } else {
                    ContentView()
                }
            }
            .buttonStyle(AppButtonFontStyle())
            .environmentObject(auth)
            .environmentObject(screenTimeManager)
            .environmentObject(notificationManager)
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                screenTimeManager.recheckAuthorization()
                screenTimeManager.applyAlwaysOnBlocking()
                screenTimeManager.registerBlockingSchedules()
            }
        }
    }
}
