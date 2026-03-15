import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore
import UIKit

@MainActor
class ProfileViewModel: ObservableObject {
    @Published var user: TuffUser = .currentUser
    @Published var leagueHistory: [LeagueHistoryEntry] = LeagueHistoryEntry.sampleHistory
    @Published var profileImage: UIImage? = nil

    var totalEarningsFormatted: String {
        let val = Int(user.totalEarnings)
        return val >= 0 ? "$\(val)" : "-$\(abs(val))"
    }

    init() {
        loadRealUser()
    }

    private func loadRealUser() {
        guard let firebaseUser = Auth.auth().currentUser else { return }

        // Load saved profile photo
        profileImage = AuthViewModel.savedProfileImage(for: firebaseUser.uid)

        // Load name from Firestore
        let uid = firebaseUser.uid
        Task {
            let db = Firestore.firestore()
            guard let doc = try? await db.collection("users").document(uid).getDocument(),
                  let data = doc.data() else { return }

            let firstName = data["firstName"] as? String ?? ""
            let lastName  = data["lastName"]  as? String ?? ""
            let fullName  = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
            let phone     = data["phone"]     as? String ?? firebaseUser.phoneNumber ?? ""

            // Patch the current-user slot with real data, keep mock stats for now
            var updated = self.user
            updated = TuffUser(
                id: updated.id,
                name: fullName.isEmpty ? "You" : fullName,
                username: phone,
                imageName: "",          // handled via profileImage
                isCurrentUser: true,
                screenTimeMinutes: updated.screenTimeMinutes,
                leagueKeys: updated.leagueKeys,
                totalLeagues: updated.totalLeagues,
                leaguesWon: updated.leaguesWon,
                totalEarnings: updated.totalEarnings
            )
            self.user = updated
        }
    }
}
