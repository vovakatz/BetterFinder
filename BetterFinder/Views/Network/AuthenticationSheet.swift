import SwiftUI

struct AuthenticationSheet: View {
    let serverName: String
    let onAuthenticate: (NetworkCredentials) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var password = ""
    @State private var saveToKeychain = false
    @FocusState private var usernameFocused: Bool

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("Authentication Required")
                .font(.headline)

            Text("Enter credentials for \"\(serverName)\"")
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                TextField("Username", text: $username)
                    .textFieldStyle(.roundedBorder)
                    .focused($usernameFocused)

                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { authenticate() }
            }

            Toggle("Remember this password in my keychain", isOn: $saveToKeychain)
                .controlSize(.small)

            HStack {
                Button("Guest") {
                    onAuthenticate(NetworkCredentials(username: "guest", password: ""))
                    dismiss()
                }

                Spacer()

                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Connect") {
                    authenticate()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(username.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear {
            // Pre-fill from keychain if credentials exist
            if let saved = KeychainService.load(for: serverName) {
                username = saved.username
                password = saved.password
                saveToKeychain = true
            }
            usernameFocused = true
        }
    }

    private func authenticate() {
        let creds = NetworkCredentials(
            username: username,
            password: password,
            saveToKeychain: saveToKeychain
        )
        onAuthenticate(creds)
        dismiss()
    }
}
