import SwiftUI

struct PhoneSignInView: View {
    @StateObject private var auth = AuthViewModel()
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Logo
                Text("TUFF")
                    .font(.system(size: 52, weight: .black, design: .default).width(.condensed))
                    .foregroundColor(.black)
                    .tracking(4)

                Text(auth.step == .phone ? "enter your number" : "check your texts")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(TuffColors.textSecondary)
                    .padding(.top, 6)

                Spacer().frame(height: 48)

                if auth.step == .phone {
                    phoneStep
                } else {
                    codeStep
                }

                Spacer()
            }
            .padding(.horizontal, 32)
        }
    }

    // MARK: - Phone step

    private var phoneStep: some View {
        VStack(spacing: 16) {
            HStack(spacing: 0) {
                Text("+1")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.leading, 16)

                Rectangle()
                    .fill(Color(hex: "E0E0E0"))
                    .frame(width: 1, height: 22)
                    .padding(.horizontal, 10)

                TextField("(555) 000-0000", text: $auth.phoneNumber)
                    .keyboardType(.phonePad)
                    .font(.system(size: 17))
                    .focused($focused)
                    .onAppear { focused = true }
                    .padding(.trailing, 16)
            }
            .frame(height: 54)
            .background(Color(hex: "F5F5F5"))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if let err = auth.errorMessage {
                Text(err)
                    .font(.system(size: 13))
                    .foregroundColor(TuffColors.negative)
                    .multilineTextAlignment(.center)
            }

            actionButton("Send Code") {
                auth.sendCode()
            }
        }
    }

    // MARK: - Code step

    private var codeStep: some View {
        VStack(spacing: 16) {
            TextField("6-digit code", text: $auth.verificationCode)
                .keyboardType(.numberPad)
                .font(.system(size: 28, weight: .bold))
                .multilineTextAlignment(.center)
                .focused($focused)
                .onAppear { focused = true }
                .frame(height: 54)
                .background(Color(hex: "F5F5F5"))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            if let err = auth.errorMessage {
                Text(err)
                    .font(.system(size: 13))
                    .foregroundColor(TuffColors.negative)
                    .multilineTextAlignment(.center)
            }

            actionButton("Verify") {
                Task { await auth.verifyCode() }
            }

            Button("Use a different number") {
                auth.step = .phone
                auth.verificationCode = ""
                auth.errorMessage = nil
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(TuffColors.textSecondary)
        }
    }

    // MARK: - Shared button

    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(TuffColors.accent)
                    .frame(height: 54)
                if auth.isLoading {
                    ProgressView().tint(.white)
                } else {
                    Text(title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                }
            }
        }
        .disabled(auth.isLoading)
    }
}

#Preview {
    PhoneSignInView()
}
