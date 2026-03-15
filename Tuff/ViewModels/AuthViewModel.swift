import Foundation
import FirebaseAuth
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
    @Published var step: Step = .phone
    @Published var phoneNumber: String = ""
    @Published var verificationCode: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil

    enum Step { case phone, code }

    private var verificationID: String? = nil
    private let uiDelegate = PhoneAuthDelegate()

    init() {
        isSignedIn = Auth.auth().currentUser != nil
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.isSignedIn = user != nil
            }
        }
    }

    func sendCode() {
        errorMessage = nil
        isLoading = true

        var number = phoneNumber.filter { $0.isNumber || $0 == "+" }
        if !number.hasPrefix("+") {
            number = "+1" + number
        }

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
            try await Auth.auth().signIn(with: credential)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() {
        try? Auth.auth().signOut()
    }
}
