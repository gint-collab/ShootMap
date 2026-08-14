//
//  AuthRepositoryProtocol.swift
//  ShootMap
//
//  Created by Septuagint Murito on 8/15/26.
//

import Foundation

// MARK: - Segregated roles

/// Read-only access to the current authentication state.
/// Views/ViewModels that only need "who is signed in?" depend on this alone.
nonisolated protocol AuthSessionProviding: Sendable {
    /// The signed-in user, or `nil` when signed out.
    func currentUser() async -> User?

    /// Emits on every authentication state change, starting with the current value.
    /// Finishes when the producer is torn down.
    var authStateUpdates: AsyncStream<User?> { get }
}

/// Credential-based authentication actions.
nonisolated protocol AuthenticationPerforming: Sendable {
    @discardableResult
    func signIn(with credentials: SignInCredentials) async throws -> User

    @discardableResult
    func signUp(with request: SignUpRequest) async throws -> User

    func signOut() async throws
}

/// Destructive / recovery account operations, kept separate because most
/// call sites never need them.
nonisolated protocol AccountManaging: Sendable {
    func sendPasswordReset(toEmail email: String) async throws
    func deleteAccount() async throws
}

// MARK: - Composed facade

/// Full authentication surface. Compose the narrow protocols above when a
/// collaborator only needs part of it.
nonisolated protocol AuthRepositoryProtocol: AuthSessionProviding, AuthenticationPerforming, AccountManaging {}
