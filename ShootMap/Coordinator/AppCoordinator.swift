//
//  AppCoordinator.swift
//  ShootMap
//
//  Created by Septuagint Murito on 8/15/26.
//

import Foundation
import Observation

// MARK: - Top-level flow

/// The mutually exclusive states the app root can be in.
///
/// Modelled as a value type so the root view is a pure function of it and the
/// coordinator cannot hold an ambiguous combination
/// (e.g. "loading *and* signed in").
nonisolated enum AppFlow: Hashable, Sendable {
    /// Auth state has not been resolved yet — show the splash screen.
    case launching
    /// No authenticated user — show the sign-in / sign-up flow.
    case authentication
    /// Authenticated — show the map and photographer features.
    case main(User)

    var authenticatedUser: User? {
        if case .main(let user) = self { return user }
        return nil
    }

    var isAuthenticated: Bool { authenticatedUser != nil }
}

// MARK: - App coordinator

/// Owns the **top-level** navigation state and nothing else.
///
/// It answers one question — "which flow should be on screen?" — by observing
/// authentication state. It performs no validation, no persistence, and knows
/// nothing about Firebase: everything reaches it through `AuthRepositoryProtocol`,
/// injected at construction.
///
/// Flow-internal navigation (pushes, sheets) belongs to the child coordinators
/// this one hands control to, not here.
@MainActor
@Observable
final class AppCoordinator {

    // MARK: Dependencies

    private let authRepository: any AuthRepositoryProtocol

    /// Used only to drop cached session data on sign-out. Optional so the
    /// coordinator stays constructible in tests that care only about auth.
    private let sessionService: (any PhotoSessionSyncServiceProtocol)?

    // MARK: Navigation state

    /// Current top-level flow. Write access is private so the flow can only
    /// change in response to authentication state, never by an arbitrary caller.
    private(set) var flow: AppFlow = .launching

    /// Surfaced so the root view can report a sign-out failure. Presentation
    /// concern only — no business meaning is attached here.
    private(set) var signOutFailed = false

    // MARK: Internals

    private var authObservationTask: Task<Void, Never>?

    // MARK: Init

    init(
        authRepository: any AuthRepositoryProtocol,
        sessionService: (any PhotoSessionSyncServiceProtocol)? = nil
    ) {
        self.authRepository = authRepository
        self.sessionService = sessionService
    }

    // MARK: Lifecycle

    /// Entry point. Begins observing authentication state; the first emission
    /// resolves `.launching` into `.authentication` or `.main`.
    func start() {
        guard authObservationTask == nil else { return }

        authObservationTask = Task { [authRepository] in
            for await user in authRepository.authStateUpdates {
                guard !Task.isCancelled else { return }
                self.apply(user)
            }
        }
    }

    /// Stops observing. Call when the root view disappears.
    func stop() {
        authObservationTask?.cancel()
        authObservationTask = nil
    }

    // MARK: Intent

    /// Requests sign-out. The repository owns the actual work; this coordinator
    /// does not flip `flow` itself — it waits for the auth stream to report the
    /// change, so there is exactly one source of truth for the flow.
    func signOut() async {
        signOutFailed = false
        do {
            try await authRepository.signOut()

            // Only after the credential is gone. Cached sessions are the
            // previous account's data and must not be visible — or writable —
            // to whoever signs in next on this device.
            try? await sessionService?.invalidateCache()
        } catch {
            signOutFailed = true
        }
    }

    func dismissSignOutFailure() {
        signOutFailed = false
    }

    // MARK: State mapping

    /// The single place authentication state becomes navigation state.
    private func apply(_ user: User?) {
        let next: AppFlow = user.map(AppFlow.main) ?? .authentication
        guard next != flow else { return }
        flow = next
    }
}
