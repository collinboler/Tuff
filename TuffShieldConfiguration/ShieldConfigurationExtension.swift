import ManagedSettings
import ManagedSettingsUI
import UIKit

class TuffShieldConfigurationExtension: ShieldConfigurationDataSource {

    // ── Brand colors ──────────────────────────────────────────────────────────
    private let tuffGreen    = UIColor(red: 0.176, green: 0.478, blue: 0.310, alpha: 1)   // #2D7A4F
    private let tuffGreenBright = UIColor(red: 0.227, green: 0.678, blue: 0.416, alpha: 1) // #3AAD6A
    private let offWhite     = UIColor(red: 0.92, green: 0.92, blue: 0.92, alpha: 1)
    private let subtitleGray = UIColor(red: 0.62, green: 0.62, blue: 0.62, alpha: 1)

    // ── Application shield ────────────────────────────────────────────────────
    override func configuration(
        shielding application: Application
    ) -> ShieldConfiguration {
        appShield()
    }

    override func configuration(
        shielding application: Application,
        in category: ActivityCategory
    ) -> ShieldConfiguration {
        appShield()
    }

    // ── Web domain shield ─────────────────────────────────────────────────────
    override func configuration(
        shielding webDomain: WebDomain
    ) -> ShieldConfiguration {
        webShield()
    }

    override func configuration(
        shielding webDomain: WebDomain,
        in category: ActivityCategory
    ) -> ShieldConfiguration {
        webShield()
    }

    // MARK: - Shield builders

    private func appShield() -> ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: UIColor.black.withAlphaComponent(0.65),
            icon: tuffIcon(),
            title: ShieldConfiguration.Label(
                text: "Locked by Tuff",
                color: .white
            ),
            subtitle: ShieldConfiguration.Label(
                text: "Open Tuff to buy a break and temporarily unlock your apps.",
                color: subtitleGray
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "Stay Focused",
                color: .white
            ),
            primaryButtonBackgroundColor: tuffGreen
        )
    }

    private func webShield() -> ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: UIColor.black.withAlphaComponent(0.65),
            icon: tuffIcon(),
            title: ShieldConfiguration.Label(
                text: "Site Locked by Tuff",
                color: .white
            ),
            subtitle: ShieldConfiguration.Label(
                text: "Open Tuff to buy a break and temporarily unlock your apps.",
                color: subtitleGray
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "Stay Focused",
                color: .white
            ),
            primaryButtonBackgroundColor: tuffGreen
        )
    }

    // MARK: - Tuff logo icon rendered as UIImage

    private func tuffIcon() -> UIImage {
        let size = CGSize(width: 120, height: 120)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: size)
            let cgCtx = ctx.cgContext

            // Circle background
            cgCtx.setFillColor(tuffGreen.cgColor)
            cgCtx.fillEllipse(in: rect)

            // "T" letter centered
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 64, weight: .black),
                .foregroundColor: UIColor.white,
            ]
            let str = NSAttributedString(string: "T", attributes: attrs)
            let strSize = str.size()
            str.draw(at: CGPoint(
                x: (size.width - strSize.width) / 2,
                y: (size.height - strSize.height) / 2
            ))
        }
    }
}
