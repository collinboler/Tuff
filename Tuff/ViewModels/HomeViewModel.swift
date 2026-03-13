import Foundation
import Combine

@MainActor
class HomeViewModel: ObservableObject {
    @Published var currentUser: TuffUser = .currentUser
    @Published var leagues: [League] = League.sampleLeagues
    @Published var selectedLeague: League?
    @Published var showLeagueDetail = false
    @Published var showCreateLeague = false

    private let screenTimeManager = ScreenTimeManager.shared

    var overallRank: Int {
        let sorted = TuffUser.allUsers.sorted { $0.screenTimeMinutes < $1.screenTimeMinutes }
        return (sorted.firstIndex(where: { $0.isCurrentUser }) ?? 0) + 1
    }

    var totalParticipants: Int {
        TuffUser.allUsers.count
    }

    var leagueNames: [String] {
        leagues.filter { $0.members.contains(where: { $0.user.isCurrentUser }) }
            .map { $0.name.uppercased() }
    }

    /// All unique users across leagues, sorted by screen time (lowest first)
    var carouselUsers: [TuffUser] {
        var seen = Set<UUID>()
        var result: [TuffUser] = []
        for user in TuffUser.allUsers.sorted(by: { $0.screenTimeMinutes < $1.screenTimeMinutes }) {
            if seen.insert(user.id).inserted {
                result.append(user)
            }
        }
        return result
    }

    func refreshData() async {
        // In production, fetch real screen time here
    }

    func selectLeague(_ league: League) {
        selectedLeague = league
        showLeagueDetail = true
    }
}
