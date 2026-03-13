import ManagedSettings
import ManagedSettingsUI
import UIKit

/// Customizes the shield UI shown when a user tries to open a blocked app.
/// This is what makes Tuff's blocking feel branded rather than generic.
///
/// To set up in Xcode:
/// 1. File > New > Target > Shield Configuration Extension
/// 2. Name it "TuffShieldConfiguration"
/// 3. Add ManagedSettings capability
class TuffShieldConfigurationExtension: ShieldConfigurationDataSource {

    override func configuration(
        shielding application: Application
    ) -> ShieldConfiguration {
        let tuffGreen = UIColor(red: 0.11, green: 0.42, blue: 0.18, alpha: 1.0)

        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: UIColor.black.withAlphaComponent(0.9),
            icon: UIImage(systemName: "lock.shield.fill"),
            title: ShieldConfiguration.Label(
                text: "Blocked by Tuff",
                color: .white
            ),
            subtitle: ShieldConfiguration.Label(
                text: "Ask a friend for the 2FA code or complete your challenge to unlock.",
                color: UIColor.lightGray
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "Enter Code",
                color: .white
            ),
            primaryButtonBackgroundColor: tuffGreen,
            secondaryButtonLabel: ShieldConfiguration.Label(
                text: "Stay Focused",
                color: UIColor.lightGray
            )
        )
    }

    override func configuration(
        shielding application: Application,
        in category: ActivityCategory
    ) -> ShieldConfiguration {
        configuration(shielding: application)
    }

    override func configuration(
        shielding webDomain: WebDomain
    ) -> ShieldConfiguration {
        let tuffGreen = UIColor(red: 0.11, green: 0.42, blue: 0.18, alpha: 1.0)

        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: UIColor.black.withAlphaComponent(0.9),
            icon: UIImage(systemName: "globe.badge.chevron.backward"),
            title: ShieldConfiguration.Label(
                text: "Site Blocked by Tuff",
                color: .white
            ),
            subtitle: ShieldConfiguration.Label(
                text: "This website is blocked during your league hours.",
                color: UIColor.lightGray
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "Enter Code",
                color: .white
            ),
            primaryButtonBackgroundColor: tuffGreen,
            secondaryButtonLabel: ShieldConfiguration.Label(
                text: "Go Back",
                color: UIColor.lightGray
            )
        )
    }

    override func configuration(
        shielding webDomain: WebDomain,
        in category: ActivityCategory
    ) -> ShieldConfiguration {
        configuration(shielding: webDomain)
    }
}
