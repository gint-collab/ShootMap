//
//  AuthError.swift
//  ShootMap
//
//  Created by Septuagint Murito on 8/17/26.
//

import Foundation

/// Application-level authentication failures.
///
/// Every provider error is translated into one of these before leaving the
/// repository, so ViewModels can switch exhaustively over a small, stable set
/// of cases without importing FirebaseAuth or matching on `NSError` codes.
nonisolated enum AuthError: Error, Equatable, Sendable {

    // MARK: Credential problems

    case invalidEmail
    case emailAlreadyInUse
    case weakPassword
    /// Wrong password, unknown account, or a malformed credential.
    ///
    /// Deliberately merged: distinguishing "no such user" from "wrong password"
    /// lets an attacker enumerate registered accounts.
    case invalidCredentials

    // MARK: Account state

    case accountDisabled
    /// The operation is sensitive and the sign-in is too old to authorise it.
    case requiresRecentLogin
    /// Signed in with Firebase, but no matching profile document exists.
    case profileMissing
    /// The operation needs a signed-in user and there is none.
    case notAuthenticated

    // MARK: Environment

    case networkUnavailable
    case tooManyRequests
    case operationNotAllowed

    /// Anything not worth modelling explicitly. Carries the provider's message
    /// for logging only — never rely on its contents for control flow.
    case unknown(message: String)
}

// MARK: - Presentation support

extension AuthError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidEmail:
            "That email address doesn't look right."
        case .emailAlreadyInUse:
            "An account already exists for that email."
        case .weakPassword:
            "Please choose a stronger password."
        case .invalidCredentials:
            "Incorrect email or password."
        case .accountDisabled:
            "This account has been disabled."
        case .requiresRecentLogin:
            "Please sign in again to continue."
        case .profileMissing:
            "We couldn't load your profile. Please try again."
        case .notAuthenticated:
            "You need to be signed in to do that."
        case .networkUnavailable:
            "No internet connection."
        case .tooManyRequests:
            "Too many attempts. Please try again later."
        case .operationNotAllowed:
            "That sign-in method isn't enabled."
        case .unknown:
            "Something went wrong. Please try again."
        }
    }
}

nonisolated extension AuthError {
    /// Whether retrying the exact same call could plausibly succeed.
    var isRetryable: Bool {
        switch self {
        case .networkUnavailable, .tooManyRequests, .unknown: true
        default: false
        }
    }
}
