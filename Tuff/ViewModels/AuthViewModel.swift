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
        isSignedIn = true   // was missing — new users were bounced back to PhoneSignInView

        let uid = user.uid
        let phone = user.phoneNumber ?? ""

        // Cache photo locally for instant display
        var imageData: Data? = nil
        if let image = profileImage, let data = image.jpegData(compressionQuality: 0.8) {
            try? data.write(to: profileImageURL(for: uid))
            imageData = data
        }

        Task {
            let db = Firestore.firestore()

            // 1. Write core profile fields immediately so the user doc exists right away
            let coreData: [String: Any] = [
                "firstName": firstName,
                "lastName": lastName,
                "username": username,
                "phone": phone,
                "createdAt": FieldValue.serverTimestamp()
            ]
            try? await db.collection("users").document(uid).setData(coreData, merge: true)

            // 2. Upload photo separately; update photoURL once we have the download URL
            guard let data = imageData else { return }
            do {
                let ref = Storage.storage().reference().child("profileImages/\(uid).jpg")
                let meta = StorageMetadata()
                meta.contentType = "image/jpeg"
                _ = try await ref.putDataAsync(data, metadata: meta)
                let url = try await ref.downloadURL()
                try await db.collection("users").document(uid).updateData([
                    "photoURL": url.absoluteString
                ])
                print("[Tuff] onboarding photo uploaded ✓")
            } catch {
                print("[Tuff] onboarding photo upload failed: \(error.localizedDescription)")
            }
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

    // MARK: - Onboarding persistence (keyed by uid so each user is independent)

    private func onboardingKey(for uid: String) -> String { "onboardingDone_\(uid)" }

    private func onboardingComplete(for uid: String) -> Bool {
        UserDefaults.standard.bool(forKey: onboardingKey(for: uid))
    }

    private func markOnboardingComplete(for uid: String) {
        UserDefaults.standard.set(true, forKey: onboardingKey(for: uid))
    }
}
