import SwiftUI

// MARK: - Colors (matched to HTML mockup CSS variables)

enum TuffColors {
    static let accent = Color(hex: "2D7A4F")
    static let accentLight = Color(hex: "3AAD6A")
    static let surface = Color(hex: "1A1A1A")
    static let background = Color.white
    static let pageBackground = Color(hex: "E0E0E0")
    static let textPrimary = Color.black
    static let textSecondary = Color(hex: "888888")
    static let gold = Color(hex: "C9940A")
    static let goldBright = Color(hex: "FFD700")
    static let silver = Color(hex: "888888")
    static let bronze = Color(hex: "A0622A")
    static let rankOther = Color(hex: "CCCCCC")
    static let negative = Color(hex: "E53935")
    static let tagBackground = Color(hex: "F0F0F0")
    static let tagText = Color(hex: "444444")
    static let divider = Color(hex: "EBEBEB")
    static let navInactive = Color(hex: "CCCCCC")
    static let modalHandle = Color(hex: "DDDDDD")
    static let modalCloseBg = Color(hex: "F0F0F0")
    static let modalCloseText = Color(hex: "666666")
    static let payoutBg = Color(hex: "FAFAFA")

    // Chart colors
    static let chartLine = Color(hex: "2D7A4F")
    static let chartGradientStart = Color(hex: "2D7A4F").opacity(0.35)
    static let chartGradientEnd = Color(hex: "2D7A4F").opacity(0.0)
    static let chartGrid = Color.white.opacity(0.06)
    static let chartLabel = Color.white.opacity(0.35)

    // Wheel
    static let wheelArc = Color(hex: "111111")
    static let slotDark = Color(hex: "1A1A1A")
    static let slotLight = Color(hex: "E8E8E8")
    static let avatarGlow = Color(hex: "2D7A4F").opacity(0.22)
    static let avatarRingInactive = Color.white.opacity(0.15)
}

// MARK: - Fonts (Barlow Condensed with system fallback)

enum TuffFonts {
    // If Barlow Condensed is bundled, these return the custom font;
    // otherwise fall back to system condensed.

    static func logo() -> Font {
        custom("BarlowCondensed-Black", size: 30, fallbackWeight: .black)
    }

    static func pageTitle() -> Font {
        custom("BarlowCondensed-Black", size: 26, fallbackWeight: .black)
    }

    static func panelName() -> Font {
        custom("BarlowCondensed-ExtraBold", size: 18, fallbackWeight: .heavy)
    }

    static func panelTime() -> Font {
        custom("BarlowCondensed-ExtraBold", size: 22, fallbackWeight: .heavy)
    }

    static func sectionHeader() -> Font {
        custom("BarlowCondensed-Bold", size: 12, fallbackWeight: .bold)
    }

    static func leagueCardName() -> Font {
        custom("BarlowCondensed-ExtraBold", size: 16, fallbackWeight: .heavy)
    }

    static func leagueCardPot() -> Font {
        custom("BarlowCondensed-ExtraBold", size: 19, fallbackWeight: .heavy)
    }

    static func newButton() -> Font {
        custom("BarlowCondensed-ExtraBold", size: 17, fallbackWeight: .heavy)
    }

    static func tag() -> Font {
        custom("BarlowCondensed-Bold", size: 10, fallbackWeight: .bold)
    }

    static func statLabel() -> Font {
        custom("BarlowCondensed-Bold", size: 10, fallbackWeight: .bold)
    }

    static func statValue() -> Font {
        custom("BarlowCondensed-ExtraBold", size: 18, fallbackWeight: .heavy)
    }

    static func streakNumber() -> Font {
        custom("BarlowCondensed-Black", size: 48, fallbackWeight: .black)
    }

    static func streakLabel() -> Font {
        custom("BarlowCondensed-ExtraBold", size: 18, fallbackWeight: .heavy)
    }

    static func profileName() -> Font {
        custom("BarlowCondensed-Black", size: 26, fallbackWeight: .black)
    }

    static func profileStatValue() -> Font {
        custom("BarlowCondensed-ExtraBold", size: 22, fallbackWeight: .heavy)
    }

    static func profileStatLabel() -> Font {
        custom("BarlowCondensed-Bold", size: 10, fallbackWeight: .bold)
    }

    static func historyName() -> Font {
        custom("BarlowCondensed-ExtraBold", size: 15, fallbackWeight: .heavy)
    }

    static func historyPayout() -> Font {
        custom("BarlowCondensed-ExtraBold", size: 16, fallbackWeight: .heavy)
    }

    static func historyRank() -> Font {
        custom("BarlowCondensed-ExtraBold", size: 13, fallbackWeight: .heavy)
    }

    static func modalTitle() -> Font {
        custom("BarlowCondensed-Black", size: 24, fallbackWeight: .black)
    }

    static func modalPot() -> Font {
        custom("BarlowCondensed-ExtraBold", size: 20, fallbackWeight: .heavy)
    }

    static func lbRank() -> Font {
        custom("BarlowCondensed-ExtraBold", size: 16, fallbackWeight: .heavy)
    }

    static func lbName() -> Font {
        custom("BarlowCondensed-ExtraBold", size: 15, fallbackWeight: .heavy)
    }

    static func lbTime() -> Font {
        custom("BarlowCondensed-ExtraBold", size: 15, fallbackWeight: .heavy)
    }

    static func togglePill() -> Font {
        custom("BarlowCondensed-Bold", size: 12, fallbackWeight: .bold)
    }

    static func payoutHeader() -> Font {
        custom("BarlowCondensed-Bold", size: 11, fallbackWeight: .bold)
    }

    static func payoutAmount() -> Font {
        custom("BarlowCondensed-ExtraBold", size: 18, fallbackWeight: .heavy)
    }

    static func caption(_ size: CGFloat = 11) -> Font {
        .system(size: size, weight: .regular)
    }

    static func body(_ size: CGFloat = 13) -> Font {
        .system(size: size, weight: .medium)
    }

    private static func custom(_ name: String, size: CGFloat, fallbackWeight: Font.Weight) -> Font {
        if UIFont(name: name, size: size) != nil {
            return .custom(name, size: size)
        }
        return .system(size: size, weight: fallbackWeight, design: .default).width(.condensed)
    }
}

// MARK: - Reusable Components

struct StatBadge: View {
    let value: String
    let label: String
    var valueColor: Color = .white

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(TuffFonts.statValue())
                .foregroundColor(valueColor)
            Text(label.uppercased())
                .font(TuffFonts.statLabel())
                .foregroundColor(.gray)
                .tracking(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(TuffColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct RankCircle: View {
    let rank: Int

    var color: Color {
        switch rank {
        case 1: return TuffColors.gold
        case 2: return TuffColors.silver
        case 3: return TuffColors.bronze
        default: return Color(hex: "444444")
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(color)
                .frame(width: 28, height: 28)
            Text("\(rank)")
                .font(TuffFonts.historyRank())
                .foregroundColor(.white)
        }
    }
}

// MARK: - Color Hex Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
