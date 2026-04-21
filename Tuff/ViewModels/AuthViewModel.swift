import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import UIKit

// Presents Firebase's reCAPTCHA web view when APNs isn't available
private class PhoneAuthDelegate: NSObject, AuthUIDelegate {
    func present(_ vc: UIViewController, animated: Bool, completion: (() -> Void)?) {
        rootVC?.present(vc, animated: animated, completion: completion)
    }
    func dismiss(animated: Bool, completion: (() -> Void)?) {
        rootVC?.dismiss(animated: animated, completion: completion)
    }
    private var rootVC: UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .rootViewController
    }
}

@MainActor
class AuthViewModel: ObservableObject {
    @Published var isSignedIn: Bool = false
    @Published var needsOnboarding: Bool = false
    @Published var step: Step = .phone
    @Published var phoneNumber: String = ""
    @Published var verificationCode: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil

    enum Step { case phone, code }

    private var verificationID: String? = nil
    private let uiDelegate = PhoneAuthDelegate()
    private var authStateListener: AuthStateDidChangeListenerHandle?

    init() {
        if let user = Auth.auth().currentUser {
            if onboardingComplete(for: user.uid) {
                isSignedIn = true
                needsOnboarding = false
            } else {
                // Firebase keychain token survived reinstall but UserDefaults was wiped.
                // Force re-authentication so the user always signs in after reinstall.
                try? Auth.auth().signOut()
                isSignedIn = false
                needsOnboarding = false
            }
        }
        authStateListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                guard let self else { return }
                guard let user else {
                    self.isSignedIn = false
                    self.needsOnboarding = false
                    return
                }
                if self.onboardingComplete(for: user.uid) {
                    self.isSignedIn = true
                    self.needsOnboarding = false
                }
                // Otherwise let verifyCode / resolveOnboardingStatus handle it
            }
        }
    }

    deinit {
        if let authStateListener {
            Auth.auth().removeStateDidChangeListener(authStateListener)
        }
    }

    // Checks Firestore to decide if onboarding is needed.
    // setSignedIn=true is used during init (keychain token still valid).
    private func resolveOnboardingStatus(for uid: String) async {
        let db = Firestore.firestore()
        let doc = try? await db.collection("users").document(uid).getDocument()
        if let data = doc?.data(), data["firstName"] != nil {
            markOnboardingComplete(for: uid)
            needsOnboarding = false
        } else {
            needsOnboarding = true
        }
    }

    // MARK: - Phone auth

    func sendCode() {
        errorMessage = nil
        isLoading = true

        var number = phoneNumber.filter { $0.isNumber || $0 == "+" }
        if !number.hasPrefix("+") { number = "+1" + number }

        PhoneAuthProvider.provider().verifyPhoneNumber(number, uiDelegate: uiDelegate) { [weak self] verificationID, error in
            Task { @MainActor [weak self] in
                self?.isLoading = false
                if let error {
                    self?.errorMessage = error.localizedDescription
                } else if let verificationID {
                    self?.verificationID = verificationID
                    self?.step = .code
                }
            }
        }
    }

    func verifyCode() async {
        guard let vid = verificationID else { return }
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        let credential = PhoneAuthProvider.provider().credential(
            withVerificationID: vid,
            verificationCode: verificationCode
        )
        do {
            let result = try await Auth.auth().signIn(with: credential)
            let uid = result.user.uid
            let isNew = result.additionalUserInfo?.isNewUser ?? false
            if isNew {
                needsOnboarding = true
            } else if onboardingComplete(for: uid) {
                needsOnboarding = false
            } else {
                // Returning user but UserDefaults cleared (reinstall) — check Firestore
                await resolveOnboardingStatus(for: uid)
                isSignedIn = true
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Onboarding

    func completeOnboarding(firstName: String, lastName: String, username: String, profileImage: UIImage? = nil) {
        guard let user = Auth.auth().currentUser else { return }
        markOnboardingComplete(for: user.uid)
        needsOnboarding = false

        let uid = user.uid
        let phone = user.phoneNumber ?? ""

        // Save profile image locally and upload to Firebase Storage
        var imageData: Data? = nil
        if let image = profileImage, let data = image.jpegData(compressionQuality: 0.8) {
            let localURL = profileImageURL(for: uid)
            try? data.write(to: localURL)
            imageData = data
        }

        Task.detached {
            let db = Firestore.firestore()
            var userData: [String: Any] = [
                "firstName": firstName,
                "lastName": lastName,
                "username": username,
                "phone": phone,
                "createdAt": FieldValue.serverTimestamp()
            ]
            if let data = imageData,
               let url = try? await StorageUploader.uploadProfilePhoto(data: data, uid: uid) {
                userData["photoURL"] = url
            }
            try? await db.collection("users").document(uid).setData(userData, merge: true)
        }
    }

    static func savedProfileImage(for uid: String) -> UIImage? {
        let url = profileImageURL(for: uid)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    static func profileImageURL(for uid: String) -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("profile_\(uid).jpg")
    }

    private func profileImageURL(for uid: String) -> URL {
        AuthViewModel.profileImageURL(for: uid)
    }

    // MARK: - Sign out / Testing

    func signOut() {
        try? Auth.auth().signOut()
    }

    /// Deletes the current Firebase account entirely so the phone number can re-register.
    /// For testing only.
    func deleteAccountForTesting() async {
        guard let user = Auth.auth().currentUser else {
            try? Auth.auth().signOut()
            return
        }
        try? await user.delete()
    }

    // MARK: - Account Deletion (App Store Guideline 5.1.1(v))

    enum DeleteAccountError: LocalizedError {
        case notSignedIn
        case requiresRecentLogin
        case reauthFailed(String)
        case deleteFailed(String)

        var errorDescription: String? {
            switch self {
            case .notSignedIn:         return "You're not signed in."
            case .requiresRecentLogin: return "Please verify your phone number again to delete your account."
            case .reauthFailed(let m): return "Verification failed: \(m)"
            case .deleteFailed(let m): return "Couldn't delete account: \(m)"
            }
        }
    }

    /// Send an SMS verification code to the current user's phone number so
    /// they can re-authenticate before we delete the account. Returns a
    /// verification ID that the caller passes back to
    /// `deleteAccount(reauthVerificationID:code:)`.
    func sendReauthCode() async throws -> String {
        guard let user = Auth.auth().currentUser,
              let phone = user.phoneNumber else {
            throw DeleteAccountError.notSignedIn
        }
        let delegate = self.uiDelegate
        return try await withCheckedThrowingContinuation { cont in
            PhoneAuthProvider.provider().verifyPhoneNumber(phone, uiDelegate: delegate) { vid, error in
                if let error {
                    cont.resume(throwing: DeleteAccountError.reauthFailed(error.localizedDescription))
                } else if let vid {
                    cont.resume(returning: vid)
                } else {
                    cont.resume(throwing: DeleteAccountError.reauthFailed("No verification ID"))
                }
            }
        }
    }

    /// Permanently delete the current user's account AND all of their data.
    /// Pass `reauthVerificationID` + `code` obtained from `sendReauthCode()`
    /// to satisfy Firebase's "recent login" requirement.
    func deleteAccount(reauthVerificationID: String, code: String) async throws {
        guard let user = Auth.auth().currentUser else {
            throw DeleteAccountError.notSignedIn
        }
        let uid = user.uid

        // 1) Re-authenticate with fresh SMS credential.
        let credential = PhoneAuthProvider.provider().credential(
            withVerificationID: reauthVerificationID,
            verificationCode: code
        )
        do {
            _ = try await user.reauthenticate(with: credential)
        } catch {
            throw DeleteAccountError.reauthFailed(error.localizedDescription)
        }

        // 2) Wipe all of this user's Firestore + Storage data while we still
        //    hold a valid auth context. Any single failure is swallowed —
        //    we prioritise completing the auth deletion so the user isn't
        //    stuck with a zombie account.
        await Self.purgeUserData(uid: uid)

        // 3) Delete the Firebase Auth record.
        do {
            try await user.delete()
        } catch {
            let ns = error as NSError
            if ns.code == AuthErrorCode.requiresRecentLogin.rawValue {
                throw DeleteAccountError.requiresRecentLogin
            }
            throw DeleteAccountError.deleteFailed(error.localizedDescription)
        }

        // 4) Clear local state (UserDefaults flag, cached profile image).
        UserDefaults.standard.removeObject(forKey: onboardingKey(for: uid))
        try? FileManager.default.removeItem(at: Self.profileImageURL(for: uid))

        // 5) Sign out to flip UI back to the phone sign-in screen.
        try? Auth.auth().signOut()
        self.isSignedIn = false
        self.needsOnboarding = false
    }

    /// Best-effort wipe of every Firestore / Storage document associated
    /// with `uid`. Called from `deleteAccount` — all failures are logged
    /// rather than thrown so a single inaccessible doc can't prevent the
    /// rest of the cleanup from running.
    private static func purgeUserData(uid: String) async {
        let db = Firestore.firestore()

        // Leagues: remove the user from memberUids so they stop getting
        // updates, and add to dqdUids so their score still counts toward
        // the pool for remaining members (same semantics as "Leave League").
        if let snap = try? await db.collection("leagues")
            .whereField("memberUids", arrayContains: uid).getDocuments() {
            await withTaskGroup(of: Void.self) { group in
                for doc in snap.documents {
                    let ref = doc.reference
                    group.addTask {
                        try? await ref.updateData([
                            "memberUids": FieldValue.arrayRemove([uid]),
                            "dqdUids":    FieldValue.arrayUnion([uid])
                        ])
                    }
                }
            }
        }

        // Posts authored by this user.
        if let snap = try? await db.collection("posts")
            .whereField("uid", isEqualTo: uid).getDocuments() {
            await withTaskGroup(of: Void.self) { group in
                for doc in snap.documents {
                    let ref = doc.reference
                    group.addTask { try? await ref.delete() }
                }
            }
        }

        // Outbound friend requests.
        if let snap = try? await db.collection("friendRequests")
            .whereField("fromUid", isEqualTo: uid).getDocuments() {
            for doc in snap.documents { try? await doc.reference.delete() }
        }
        // Inbound friend requests.
        if let snap = try? await db.collection("friendRequests")
            .whereField("toUid", isEqualTo: uid).getDocuments() {
            for doc in snap.documents { try? await doc.reference.delete() }
        }

        // My friends subcollection + mirror entries on each friend's side.
        if let friendsSnap = try? await db.collection("users").document(uid)
            .collection("friends").getDocuments() {
            for doc in friendsSnap.documents {
                let friendUid = doc.documentID
                try? await db.collection("users").document(friendUid)
                    .collection("friends").document(uid).delete()
                try? await doc.reference.delete()
            }
        }

        // User document itself.
        try? await db.collection("users").document(uid).delete()

        // Profile photo in Storage (best-effort — ignored if missing).
        let ref = Storage.storage().reference().child("profileImages/\(uid).jpg")
        _ = try? await ref.delete()
    }

    // MARK: - Onboarding persistence (keyed by uid so each user is independent)

    private func onboardingKey(for uid: String) -> String { "onboardingDone_\(uid)" }

    private func onboardingComplete(for uid: String) -> Bool {
        UserDefaults.standard.bool(forKey: onboardingKey(for: uid))
    }

    private func markOnboardingComplete(for uid: String) {
        UserDefaults.standard.set(true, forKey: onboardingKey(for: uid))
    }
}
