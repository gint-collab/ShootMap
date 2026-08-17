//
//  LoginViewModel.swift
//  ShootMap
//
//  Created by Septuagint Murito on 8/17/26.
//

import Foundation
import Observation

/// Drives the Login screen.
///
/// Holds only form state and the result of the sign-in attempt. It authenticates
/// through `AuthRepositoryProtocol` and expresses navigation as intent through
/// `AuthNavigating`, so it never sees Firebase, SwiftData, a `NavigationStack`,
/// or a navigation path.
@MainActor
@Observable
final class LoginViewModel {

    // MARK: - Form state

    var email: String = "" {
        didSet { clearErrorOnEdit(oldValue, email) }
    }

    var password: String = "" {
        didSet { clearErrorOnEdit(oldValue, password) }
    }

    // MARK: - View state

    /// Mutually exclusive states, so the view cannot render "loading" and
    /// "failed" at the same time.
    enum State: Equatable {
        case idle
        case loading
        case failed(AuthError)

        var isLoading: Bool { self == .loading }

        var error: AuthError? {
            if case let .failed(error) = self { return error }
            return nil
        }
    }

    private(set) var state: State = .idle

    /// Message for the view to display, or `nil` when there is nothing to show.
    /// The view formats it; the ViewModel does not build any UI.
    var errorMessage: String? { state.error?.errorDescription }

    var isLoading: Bool { state.isLoading }

    /// Local pre-check only. The authoritative validation belongs to the auth
    /// provider — this exists purely to disable the button on obvious input.
    var canSubmit: Bool {
        !isLoading
            && EmailFormat.isValid(email)
            && !password.isEmpty
    }

    // MARK: - Dependencies

    private let authRepository: any AuthRepositoryProtocol

    /// `weak` because the coordinator owns this ViewModel; a strong reference
    /// back would be a retain cycle.
    private weak var navigator: (any AuthNavigating)?

    // MARK: - Init

    init(
        authRepository: any AuthRepositoryProtocol,
        navigator: (any AuthNavigating)?
    ) {
        self.authRepository = authRepository
        self.navigator = navigator
    }

    // MARK: - Intent

    /// Authenticates, then hands the result to the coordinator.
    ///
    /// The ViewModel decides *when* navigation should happen; the coordinator
    /// decides *what* that means.
    func login() async {
        guard canSubmit else { return }

        state = .loading
        do {
            let user = try await authRepository.signIn(
                with: SignInCredentials(email: email, password: password)
            )
            state = .idle
            // Clear the credential as soon as it is no longer needed rather than
            // leaving it in memory for the lifetime of the screen.
            password = ""
            navigator?.authenticationDidSucceed(with: user)
        } catch {
            // The repository already translates provider errors, so this is the
            // safety net for anything unexpected — not a Firebase mapping site.
            state = .failed(error as? AuthError ?? .unknown(message: error.localizedDescription))
        }
    }

    func showSignUp() {
        navigator?.showSignUp()
    }

    func showForgotPassword() {
        navigator?.showForgotPassword()
    }

    /// Lets the view dismiss an error banner.
    func dismissError() {
        guard state.error != nil else { return }
        state = .idle
    }

    // MARK: - Helpers

    /// Drops a stale failure as soon as the user edits the form, so the error
    /// never outlives the input that caused it.
    private func clearErrorOnEdit(_ oldValue: String, _ newValue: String) {
        guard oldValue != newValue, state.error != nil else { return }
        state = .idle
    }
}
