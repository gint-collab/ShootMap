//
//  LoginView.swift
//  ShootMap
//
//  Created by Septuagint Murito on 8/17/26.
//

import SwiftUI

/// The Login screen.
///
/// Presentation only: it renders `LoginViewModel`'s state and forwards user
/// gestures back to it. It performs no validation, no authentication, and no
/// navigation of its own — `Sign Up` calls a ViewModel intent, which reaches
/// the coordinator.
struct LoginView: View {

    @State private var viewModel: LoginViewModel

    /// Which field currently holds the keyboard, so Return can move between them.
    @FocusState private var focusedField: Field?
    @State private var isPasswordVisible = false

    private enum Field: Hashable {
        case email
        case password
    }

    init(viewModel: LoginViewModel) {
        _viewModel = State(wrappedValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                errorBanner
                form
                actions
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 32)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Sign In")
        .navigationBarTitleDisplayMode(.inline)
        // Blocks interaction for the duration of the request without swapping
        // the whole screen for a spinner, so the form stays visible.
        .disabled(viewModel.isLoading)
        .animation(.default, value: viewModel.errorMessage)
        .animation(.default, value: viewModel.isLoading)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "camera.on.rectangle")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            Text("Welcome to ShootMap")
                .font(.title2.weight(.semibold))

            Text("Sign in to discover photo sessions near you.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, 8)
    }

    // MARK: - Error

    @ViewBuilder
    private var errorBanner: some View {
        if let message = viewModel.errorMessage {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .accessibilityHidden(true)

                Text(message)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    viewModel.dismissError()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Dismiss error")
            }
            .padding(12)
            .background(.red.opacity(0.12), in: .rect(cornerRadius: 12))
            // Announced by VoiceOver the moment it appears.
            .accessibilityElement(children: .combine)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: - Form

    private var form: some View {
        VStack(spacing: 16) {
            VStack(spacing: 20) {
                field(title: "Email") {
                    HStack(spacing: 12) {
                        Image(systemName: "envelope")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        TextField("you@example.com", text: $viewModel.email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .email)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .password }
                    }
                }

                field(title: "Password") {
                    HStack(spacing: 12) {
                        Image(systemName: "lock")
                            .font(.title3)
                            .foregroundStyle(.secondary)

                        Group {
                            if isPasswordVisible {
                                TextField("••••••••", text: $viewModel.password)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                            } else {
                                SecureField("••••••••", text: $viewModel.password)
                            }
                        }
                        .textContentType(.password)
                        .focused($focusedField, equals: .password)
                        .submitLabel(.go)
                        .onSubmit { Task { await viewModel.login() } }

                        Button {
                            isPasswordVisible.toggle()
                        } label: {
                            Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isPasswordVisible ? "Hide password" : "Show password")
                    }
                }
            }

            Button("Forgot password?") {
                viewModel.showForgotPassword()
            }
            .font(.footnote)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
    
    private func field<Content: View>(title: String,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            content()
                .padding(.horizontal, 18)
                .padding(.vertical, 18)
                .background(Color(.systemGray6),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: 16) {
            Button(action: submit) {
                Group {
                    if viewModel.isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    } else {
                        Text("Sign In")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 24)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            // `canSubmit` already accounts for the loading state.
            .disabled(!viewModel.canSubmit)
            .accessibilityLabel(viewModel.isLoading ? "Signing in" : "Sign in")

            HStack(spacing: 4) {
                Text("Don't have an account?")
                    .foregroundStyle(.secondary)

                Button("Sign Up") {
                    viewModel.showSignUp()
                }
                .fontWeight(.semibold)
            }
            .font(.subheadline)
        }
    }

    // MARK: - Intent

    private func submit() {
        // Dismiss the keyboard so the error banner and spinner are visible.
        focusedField = nil
        Task { await viewModel.login() }
    }
}

// MARK: - Preview

#if DEBUG
/// Preview-only stub. Not a repository implementation — it talks to nothing and
/// exists solely so the canvas can render without a backend.
private final class PreviewAuthRepository: AuthRepositoryProtocol, @unchecked Sendable {
    let result: Result<User, AuthError>

    init(result: Result<User, AuthError> = .failure(.invalidCredentials)) {
        self.result = result
    }

    func currentUser() async -> User? { nil }
    var authStateUpdates: AsyncStream<User?> { AsyncStream { $0.finish() } }

    func signIn(with credentials: SignInCredentials) async throws -> User {
        try await Task.sleep(for: .seconds(1))
        return try result.get()
    }

    func signUp(with request: SignUpRequest) async throws -> User { try result.get() }
    func signOut() async throws {}
    func sendPasswordReset(toEmail email: String) async throws {}
    func deleteAccount() async throws {}
}

#Preview("Login") {
    NavigationStack {
        LoginView(
            viewModel: LoginViewModel(
                authRepository: PreviewAuthRepository(),
                navigator: nil
            )
        )
    }
}
#endif
