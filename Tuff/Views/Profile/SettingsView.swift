import SwiftUI
import FirebaseAuth

struct SettingsView: View {
    @EnvironmentObject var auth: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showSignOutConfirm = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button(role: .destructive) {
                        showSignOutConfirm = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(.system(size: 16))
                                .frame(width: 28)
                            Text("Sign Out")
                                .font(.system(size: 16))
                        }
                        .foregroundColor(.red)
                    }
                }
                .listRowBackground(Color.white)

                Section {
                    HStack {
                        Text("Version")
                            .foregroundColor(.black)
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            .foregroundColor(TuffColors.textSecondary)
                    }
                } header: {
                    Text("About")
                }
                .listRowBackground(Color.white)
            }
            .listStyle(.insetGrouped)
            .background(Color(hex: "F5F5F5"))
            .scrollContentBackground(.hidden)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .colorScheme(.light)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(TuffColors.accent)
                }
            }
        }
        .confirmationDialog("Sign out?", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) {
                try? Auth.auth().signOut()
            }
        }
    }
}
