import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import UIKit
import SwiftUI

@MainActor
class ProfileViewModel: ObservableObject {
    @Published var user: TuffUser = .currentUser
    @Published var leagueHistory: [LeagueHistoryEntry] = []
    @Published var profileImage: UIImage? = nil
    @Published var friendsCount: Int = 0

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

        // Upload image to Firebase Storage and persist URL to Firestore + local cache
        var photoURLString: String? = nil
        if let img = image, let data = img.jpegData(compressionQuality: 0.8) {
            let ref = Storage.storage().reference().child("profileImages/\(uid).jpg")
            do {
                let meta = StorageMetadata()
                meta.contentType = "image/jpeg"
                _ = try await ref.putDataAsync(data, metadata: meta)
                let downloadURL = try await ref.downloadURL()
                photoURLString = downloadURL.absoluteString
            } catch {
                return "Photo upload failed: \(error.localizedDescription)"
            }
            // Cache locally so the current device doesn't re-download
            let localURL = AuthViewModel.profileImageURL(for: uid)
            try? data.write(to: localURL)
            profileImage = img
        }

        // Save to Firestore
        var firestoreUpdate: [String: Any] = [
            "firstName": firstName.trimmingCharacters(in: .whitespaces),
            "lastName": lastName.trimmingCharacters(in: .whitespaces),
            "username": trimmedUsername
        ]
        if let url = photoURLString { firestoreUpdate["photoURL"] = url }
        do {
            try await db.collection("users").document(uid).updateData(firestoreUpdate)
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
        let uid = firebaseUser.uid

        // Load locally cached photo first for instant display
        profileImage = AuthViewModel.savedProfileImage(for: uid)

        Task {
            let db = Firestore.firestore()
            guard let doc = try? await db.collection("users").document(uid).getDocument(),
                  let data = doc.data() else { return }

            let firstName = data["firstName"] as? String ?? ""
            let lastName  = data["lastName"]  as? String ?? ""
            let fullName  = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
            let phone     = data["phone"]     as? String ?? firebaseUser.phoneNumber ?? ""

            self.user = TuffUser(
                id: self.user.id,
                uid: uid,
                name: fullName.isEmpty ? "You" : fullName,
                username: data["username"] as? String ?? phone,
                imageName: "",
                isCurrentUser: true,
                screenTimeMinutes: self.user.screenTimeMinutes,
                totalLeagues: self.user.totalLeagues,
                leaguesWon: self.user.leaguesWon,
                totalEarnings: self.user.totalEarnings
            )

            // If there's a remote photo and no local cache, download it
            if self.profileImage == nil,
               let photoURLString = data["photoURL"] as? String,
               let photoURL = URL(string: photoURLString),
               let (imgData, _) = try? await URLSession.shared.data(from: photoURL),
               let img = UIImage(data: imgData) {
                let localURL = AuthViewModel.profileImageURL(for: uid)
                try? imgData.write(to: localURL)
                self.profileImage = img
            }
        }

        // Load friends count from leagues
        Task {
            let db = Firestore.firestore()
            guard let snap = try? await db.collection("leagues")
                .whereField("memberUids", arrayContains: uid)
                .getDocuments() else { return }
            var friendUids = Set<String>()
            for doc in snap.documents {
                let uids = doc.data()["memberUids"] as? [String] ?? []
                for u in uids where u != uid { friendUids.insert(u) }
            }
            self.friendsCount = friendUids.count
        }
    }
}
