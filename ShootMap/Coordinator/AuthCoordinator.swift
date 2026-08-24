//
//  AuthCoordinator.swift
//  ShootMap
//
//  Created by Septuagint Murito on 8/15/26.
//

import Foundation
import Observation

// MARK: - Routes

/// Destinations reachable inside the authentication flow.
///
/// Login is the flow's root, so it is *not* a route — it is where an empty
/// `path` lands. Only pushed/presented screens need a case.
nonisolated enum AuthRoute: RouteRepresentable {
    case signUp
    case forgotPassword
}

// MARK: - Dependencies

/// What the auth flow needs in order to build its child ViewModels.
///
/// A protocol rather than a concrete container so the flow can be constructed
/// in tests with a stub, and so no Firebase type is ever named here.
nonisolated protocol AuthFlowDependencies: Sendable {
    var authRepository: any AuthRepositoryProtocol { get }
}

// MARK: - Coordinator

/// Owns navigation for the authentication flow: Login ⇄ Sign Up.
///
/// Strictly navigation. It never signs anyone in, never validates a field, and
/// never touches Firebase — the child ViewModels do that through
/// `AuthRepositoryProtocol` and simply *tell* this coordinator when they are done.
///
/// Completion is reported upward via `onFinish`, so `AppCoordinator` decides what
/// happens next; this coordinator has no knowledge of its parent.
@MainActor
@Observable
final class AuthCoordinator: RouterProtocol, FlowCompleting {

    // MARK: Navigation state

    var path: [AuthRoute] = []
    var presentedRoute: PresentedRoute<AuthRoute>?

    // MARK: Flow completion

    /// Called once authentication succeeds. `AppCoordinator` assigns this.
    var onFinish: ((User) -> Void)?

    // MARK: Dependencies

    /// Handed to child ViewModels when they are constructed. The coordinator
    /// itself never calls into it.
    let dependencies: any AuthFlowDependencies

    // MARK: Init

    init(dependencies: any AuthFlowDependencies) {
        self.dependencies = dependencies
    }

    // MARK: Lifecycle

    /// Entry point — the flow always opens on Login.
    func start() {
        popToRoot()
        dismiss()
    }

    // MARK: Navigation intent
    //
    // Named for what the user wants, not for the mechanism, so ViewModels stay
    // free of stack semantics (`push` / `pop` never appear in a ViewModel).

    func showSignUp() {
        push(.signUp)
    }

    func showLogin() {
        popToRoot()
    }

    func showForgotPassword() {
        present(.forgotPassword, style: .sheet)
    }

    func closeForgotPassword() {
        dismiss()
    }

    // MARK: Flow outcome

    /// Called by the Login or Sign Up ViewModel after the repository reports a
    /// successful authentication. The coordinator only forwards the result — it
    /// does not verify or persist anything.
    func authenticationDidSucceed(with user: User) {
        dismiss()
        popToRoot()
        onFinish?(user)
    }
}
