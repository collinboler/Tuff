import Foundation
import FirebaseAuth
import FirebaseFirestore
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

    init() {
        if let user = Auth.auth().currentUser {
            if onboardingComplete(for: user.uid) {
                // Returning user — go straight to main app
                isSignedIn = true
                needsOnboarding = false
            } else {
                // Firebase keychain token survived a reinstall but UserDefaults was wiped.
                // Sign out so they go through phone verification first.
                try? Auth.auth().signOut()
                isSignedIn = false
                needsOnboarding = false
            }
        }
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                guard let self else { return }
                if let user {
                    self.isSignedIn = true
                    self.needsOnboarding = !self.onboardingComplete(for: user.uid)
                } else {
                    self.isSignedIn = false
                    self.needsOnboarding = false
                }
            }
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
            let isNew = result.additionalUserInfo?.isNewUser ?? false
            if isNew {
                needsOnboarding = true
            } else {
                needsOnboarding = !onboardingComplete(for: result.user.uid)
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

        // Save profile image to local documents directory
        if let image = profileImage,
           let data = image.jpegData(compressionQuality: 0.8) {
            let url = profileImageURL(for: user.uid)
            try? data.write(to: url)
        }

        let uid = user.uid
        let phone = user.phoneNumber ?? ""
        Task.detached {
            let db = Firestore.firestore()
            try? await db.collection("users").document(uid).setData([
                "firstName": firstName,
                "lastName": lastName,
                "username": username,
                "phone": phone,
                "createdAt": FieldValue.serverTimestamp()
            ], merge: true)
        }
    }

    static func savedProfileImage(for uid: String) -> UIImage? {
        let url = profileImageURL(for: uid)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    private static func profileImageURL(for uid: String) -> URL {
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
