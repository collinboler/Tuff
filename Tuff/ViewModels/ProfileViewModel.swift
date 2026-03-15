import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore
import UIKit
import SwiftUI

@MainActor
class ProfileViewModel: ObservableObject {
    @Published var user: TuffUser = .currentUser
    @Published var leagueHistory: [LeagueHistoryEntry] = []
    @Published var profileImage: UIImage? = nil

    var totalEarningsFormatted: String {
        let val = Int(user.totalEarnings)
        return val >= 0 ? "$\(val)" : "-$\(abs(val))"
    }

    init() {
        loadRealUser()
    }

    func updateProfile(firstName: String, lastName: String, username: String, image: UIImage?) async -> String? {
        guard let firebaseUser = Auth.auth().currentUser else { return "Not signed in" }
        let uid = firebaseUser.uid
        let db = Firestore.firestore()

        // Check username availability if changed
        let trimmedUsername = username.trimmingCharacters(in: .whitespaces).lowercased()
        if trimmedUsername != user.username {
            do {
                let snap = try await db.collection("users")
                    .whereField("username", isEqualTo: trimmedUsername)
                    .limit(to: 1)
                    .getDocuments()
                if !snap.documents.isEmpty {
                    return "@\(trimmedUsername) is already taken"
                }
            } catch {
                return error.localizedDescription
            }
        }

        // Save image locally
        if let img = image, let data = img.jpegData(compressionQuality: 0.8) {
            let url = AuthViewModel.profileImageURL(for: uid)
            try? data.write(to: url)
            profileImage = img
        }

        // Save to Firestore
        do {
            try await db.collection("users").document(uid).updateData([
                "firstName": firstName.trimmingCharacters(in: .whitespaces),
                "lastName": lastName.trimmingCharacters(in: .whitespaces),
                "username": trimmedUsername
            ])
        } catch {
            return error.localizedDescription
        }

        // Update local user
        let fullName = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
        user = TuffUser(
            id: user.id, uid: uid,
            name: fullName.isEmpty ? "You" : fullName,
            username: trimmedUsername,
            imageName: "",
            isCurrentUser: true,
            screenTimeMinutes: user.screenTimeMinutes,
            totalLeagues: user.totalLeagues,
            leaguesWon: user.leaguesWon,
            totalEarnings: user.totalEarnings
        )
        return nil
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
                uid: firebaseUser.uid,
                name: fullName.isEmpty ? "You" : fullName,
                username: data["username"] as? String ?? phone,
                imageName: "",
                isCurrentUser: true,
                screenTimeMinutes: updated.screenTimeMinutes,
                totalLeagues: updated.totalLeagues,
                leaguesWon: updated.leaguesWon,
                totalEarnings: updated.totalEarnings
            )
            self.user = updated
        }
    }
}
