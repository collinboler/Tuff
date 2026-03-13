import Foundation
import Combine

@MainActor
class ProfileViewModel: ObservableObject {
    @Published var user: TuffUser = .currentUser
    @Published var leagueHistory: [LeagueHistoryEntry] = LeagueHistoryEntry.sampleHistory

    var totalEarningsFormatted: String {
        "$\(Int(user.totalEarnings))"
    }
}
