//
//  AuthCoordinator+Views.swift
//  ShootMap
//
//  Created by Septuagint Murito on 8/20/26.
//

import SwiftUI

/// Completes `AuthCoordinator` into a full `CoordinatorProtocol` by supplying the
/// route → view mapping.
///
/// Kept in a separate file so the coordinator itself stays free of SwiftUI and
/// remains testable as pure navigation logic.
extension AuthCoordinator: CoordinatorProtocol {

    /// Login is the flow's root — it has no route, so an empty path *is* login.
    func rootView() -> some View {
        LoginView(
            viewModel: LoginViewModel(
                authRepository: dependencies.authRepository,
                navigator: self
            )
        )
    }

    @ViewBuilder
    func view(for route: AuthRoute) -> some View {
        switch route {
        case .signUp:
            SignUpView(
                viewModel: SignUpViewModel(
                    authRepository: dependencies.authRepository,
                    navigator: self
                )
            )

        case .forgotPassword:
            ForgotPasswordView(
                authRepository: dependencies.authRepository,
                onClose: { [weak self] in self?.closeForgotPassword() }
            )
        }
    }
}

// MARK: - Forgot password
//
// Small enough that a dedicated ViewModel would add indirection without value;
// it owns one field and one repository call.

struct ForgotPasswordView: View {

    let authRepository: any AccountManaging
    let onClose: () -> Void

    @State private var email = ""
    @State private var isSending = false
    @State private var message: String?
    @State private var didSend = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text("We'll send you a link to reset your password.")
                }

                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(didSend ? .green : .red)
                }

                Section {
                    Button {
                        Task { await send() }
                    } label: {
                        HStack {
                            Spacer()
                            if isSending { ProgressView() } else { Text("Send Reset Link") }
                            Spacer()
                        }
                    }
                    .disabled(!EmailFormat.isValid(email) || isSending)
                }
            }
            .navigationTitle("Reset Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onClose)
                }
            }
        }
    }

    private func send() async {
        isSending = true
        defer { isSending = false }

        do {
            try await authRepository.sendPasswordReset(toEmail: email)
            didSend = true
            // Deliberately does not confirm whether the address is registered —
            // that would turn this screen into an account-enumeration oracle.
            message = "If that email has an account, a reset link is on its way."
        } catch {
            didSend = false
            message = (error as? LocalizedError)?.errorDescription
                ?? "Couldn't send the reset link."
        }
    }
}
