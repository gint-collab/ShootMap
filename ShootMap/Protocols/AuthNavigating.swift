//
//  AuthNavigating.swift
//  ShootMap
//
//  Created by Septuagint Murito on 8/17/26.
//

import Foundation

/// The navigation vocabulary the authentication screens need.
///
/// Deliberately narrow: it exposes *intent* (`showSignUp`) and never mechanism
/// (`push` / `pop` / `path`). A ViewModel holding this cannot reach the
/// navigation stack, cannot build a view, and cannot know it is driving an
/// `AuthCoordinator` — which is what keeps navigation logic out of the ViewModel
/// by construction rather than by convention.
///
/// `@MainActor` because navigation state is main-actor state; `AnyObject` so
/// ViewModels can hold it `weak` and avoid a retain cycle with the coordinator.
@MainActor
protocol AuthNavigating: AnyObject {

    /// Move from Login to Sign Up.
    func showSignUp()

    /// Return to Login from anywhere in the flow.
    func showLogin()

    /// Present password recovery.
    func showForgotPassword()

    /// Report a completed authentication so the parent flow can take over.
    /// Called *after* the repository confirms success — this never authenticates.
    func authenticationDidSucceed(with user: User)
}

// MARK: - Conformance

/// The concrete coordinator already speaks exactly this vocabulary, so adopting
/// the protocol adds no code — it only narrows what ViewModels can see.
extension AuthCoordinator: AuthNavigating {}
