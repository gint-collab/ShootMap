//
//  SignUpViewModel.swift
//  ShootMap
//
//  Created by Septuagint Murito on 8/20/26.
//

import Foundation
import Observation

/// Creates an account and reports success to the auth flow.
///
/// Imports only `Foundation` and `Observation` — no Firebase, no SwiftData,
/// no SwiftUI. Navigation goes through `AuthNavigating`.
@MainActor
@Observable
final class SignUpViewModel {

    /// The role a new account is created with.
    ///
    /// Only the two self-selectable roles are offered; `admin` is granted
    /// out-of-band and is deliberately not representable here — mirroring the
    /// Firestore rule that rejects a client-supplied `admin` role.
    enum AccountType: String, CaseIterable, Identifiable, Sendable {
        case viewer
        case photographer

        var id: String { rawValue }

        var title: String {
            switch self {
            case .viewer: "Viewer"
            case .photographer: "Photographer"
            }
        }

        var explanation: String {
            switch self {
            case .viewer: "Browse photo sessions happening near you."
            case .photographer: "Pin your shoots so people can find you."
            }
        }

        var role: UserRole {
            switch self {
            case .viewer: .client
            case .photographer: .photographer
            }
        }
    }

    // MARK: - Form state

    var email = "" { didSet { clearErrorOnEdit() } }
    var password = "" { didSet { clearErrorOnEdit() } }
    var displayName = "" { didSet { clearErrorOnEdit() } }
    var accountType: AccountType = .viewer { didSet { clearErrorOnEdit() } }

    /// Photographer-only. The domain requires a page for that role.
    var facebookPageName = "" { didSet { clearErrorOnEdit() } }
    var facebookPageURL = "" { didSet { clearErrorOnEdit() } }

    // MARK: - Status

    private(set) var isRegistering = false
    private(set) var errorMessage: String?

    // MARK: - Derived

    var requiresFacebookPage: Bool { accountType.role.requiresFacebookPage }

    var canSubmit: Bool {
        guard !isRegistering,
              EmailFormat.isValid(email),
              password.count >= Self.minimumPasswordLength,
              !displayName.trimmed.isEmpty else { return false }

        // Enforced here so the button state matches what the domain will accept.
        if requiresFacebookPage {
            return !facebookPageName.trimmed.isEmpty || !facebookPageURL.trimmed.isEmpty
        }
        return true
    }

    static let minimumPasswordLength = 6

    // MARK: - Dependencies

    private let authRepository: any AuthenticationPerforming
    private weak var navigator: (any AuthNavigating)?

    init(
        authRepository: any AuthenticationPerforming,
        navigator: (any AuthNavigating)? = nil
    ) {
        self.authRepository = authRepository
        self.navigator = navigator
    }

    func setNavigator(_ navigator: any AuthNavigating) {
        self.navigator = navigator
    }

    // MARK: - Actions

    func signUp() async {
        guard canSubmit else { return }

        errorMessage = nil
        isRegistering = true
        defer { isRegistering = false }

        do {
            let user = try await authRepository.signUp(with: makeRequest())
            password = ""   // do not keep the credential in memory
            navigator?.authenticationDidSucceed(with: user)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Couldn't create your account. Please try again."
        }
    }

    func showLogin() {
        navigator?.showLogin()
    }

    func dismissError() {
        errorMessage = nil
    }

    // MARK: - Private

    private func makeRequest() -> SignUpRequest {
        SignUpRequest(
            email: email.trimmed,
            password: password,
            displayName: displayName.trimmed,
            role: accountType.role,
            facebookPageName: requiresFacebookPage ? facebookPageName.trimmedNonEmpty : nil,
            facebookPageURL: requiresFacebookPage ? normalizedPageURL : nil
        )
    }

    /// Accepts "facebook.com/name" as well as a full URL, so a user pasting the
    /// address bar contents is not rejected for a missing scheme.
    private var normalizedPageURL: URL? {
        let trimmed = facebookPageURL.trimmed
        guard !trimmed.isEmpty else { return nil }
        if trimmed.lowercased().hasPrefix("http") {
            return URL(string: trimmed)
        }
        return URL(string: "https://\(trimmed)")
    }

    private func clearErrorOnEdit() {
        if errorMessage != nil { errorMessage = nil }
    }
}
