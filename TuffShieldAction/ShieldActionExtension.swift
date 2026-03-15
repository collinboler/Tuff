import Foundation
import ManagedSettings
import ManagedSettingsUI

class TuffShieldActionExtension: ShieldActionDelegate {

    override func handle(
        action: ShieldAction,
        for application: ApplicationToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        switch action {
        case .primaryButtonPressed:
            // Wait 5 seconds, then remove shields and let the app open
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                let store = ManagedSettingsStore()
                store.shield.applications = nil
                store.shield.applicationCategories = nil
                completionHandler(.close)
            }
        case .secondaryButtonPressed:
            // "Stay Focused" — keep app blocked, go back
            completionHandler(.close)
        @unknown default:
            completionHandler(.close)
        }
    }

    override func handle(
        action: ShieldAction,
        for category: ActivityCategoryToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        switch action {
        case .primaryButtonPressed:
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                let store = ManagedSettingsStore()
                store.shield.applications = nil
                store.shield.applicationCategories = nil
                completionHandler(.close)
            }
        default:
            completionHandler(.close)
        }
    }

    override func handle(
        action: ShieldAction,
        for webDomain: WebDomainToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        switch action {
        case .primaryButtonPressed:
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                let store = ManagedSettingsStore()
                store.shield.webDomains = nil
                completionHandler(.close)
            }
        default:
            completionHandler(.close)
        }
    }
}
