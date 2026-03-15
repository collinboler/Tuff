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
            // Wait 5 seconds, then unblock ONLY this specific app
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                let store = ManagedSettingsStore()
                // Remove just this app from the blocked set, keep others blocked
                if var blocked = store.shield.applications {
                    blocked.remove(application)
                    store.shield.applications = blocked.isEmpty ? nil : blocked
                }
                completionHandler(.close)
            }

        case .secondaryButtonPressed:
            // "Stay Focused" — keep blocked, return to home screen
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
                // For category-level blocks, clear all shields after the wait
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
                store.shield.webDomainCategories = nil
                completionHandler(.close)
            }
        default:
            completionHandler(.close)
        }
    }
}
