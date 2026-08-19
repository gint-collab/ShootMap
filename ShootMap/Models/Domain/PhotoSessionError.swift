//
//  PhotoSessionError.swift
//  ShootMap
//
//  Created by Septuagint Murito on 8/17/26.
//

import Foundation

/// Application-level failures for photo session storage.
///
/// Every provider error is translated into one of these before leaving the
/// repository, so ViewModels switch over a small, stable set of cases without
/// importing FirebaseFirestore or matching on `NSError` codes.
nonisolated enum PhotoSessionError: Error, Equatable, Sendable {

    // MARK: Authorisation

    /// The operation needs a signed-in photographer and there is none.
    case notAuthenticated

    /// The signed-in user is not the author of this session.
    case notSessionOwner

    /// The signed-in user's role cannot publish sessions.
    case notPermittedToPublish

    // MARK: Data

    case sessionNotFound(id: String)

    /// The stored document could not be read as a `PhotoSession`.
    case malformedSession(id: String)

    /// The session failed domain validation before it was ever sent.
    case invalid(DomainValidationError)

    // MARK: Environment

    case networkUnavailable
    case permissionDenied
    case quotaExceeded

    /// The local cache could not be read or written (disk full, migration
    /// failure, corrupt store). Distinct from the network cases because it is
    /// a device-local problem that retrying rarely fixes.
    case cacheFailure(message: String)

    case unknown(message: String)
}

// MARK: - Presentation support

extension PhotoSessionError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            "You need to be signed in to do that."
        case .notSessionOwner:
            "You can only change sessions you created."
        case .notPermittedToPublish:
            "Only photographers can publish sessions."
        case .sessionNotFound:
            "That session no longer exists."
        case .malformedSession:
            "That session couldn't be loaded."
        case let .invalid(error):
            // `DomainValidationError` intentionally carries no UI strings, so
            // the user-facing wording is chosen here.
            Self.message(for: error)
        case .networkUnavailable:
            "No internet connection."
        case .permissionDenied:
            "You don't have permission to do that."
        case .quotaExceeded:
            "The service is busy. Please try again shortly."
        case .cacheFailure:
            "Couldn't read saved sessions on this device."
        case .unknown:
            "Something went wrong. Please try again."
        }
    }
}

nonisolated extension PhotoSessionError {
    /// Whether retrying the same call could plausibly succeed.
    var isRetryable: Bool {
        switch self {
        case .networkUnavailable, .quotaExceeded, .unknown: true
        default: false
        }
    }

    /// Wording for the validation failures a session can realistically hit.
    fileprivate static func message(for error: DomainValidationError) -> String {
        switch error {
        case .endTimeNotAfterStartTime:
            "The end time must be after the start time."
        case .sessionDurationTooShort:
            "Sessions must run for at least 5 minutes."
        case .sessionDurationTooLong:
            "Sessions can't run longer than 24 hours."
        case .sessionTimesNotOnSessionDate:
            "The start and end times must fall on the session date."
        case .invalidLatitude, .invalidLongitude:
            "Please pick a valid location on the map."
        case .emptyDisplayName:
            "A photographer name is required."
        default:
            "That session isn't valid."
        }
    }
}
