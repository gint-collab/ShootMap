//
//  DomainValidationError.swift
//  ShootMap
//
//  Created by Septuagint Murito on 8/15/26.
//

import Foundation

/// Pure-domain validation failures. No UI strings, no localization concerns.
nonisolated enum DomainValidationError: Error, Equatable, Sendable {
    case emptyIdentifier
    case invalidEmail(String)
    case emptyDisplayName
    case invalidLatitude(Double)
    case invalidLongitude(Double)
    case endTimeNotAfterStartTime(start: Date, end: Date)
    case sessionTimesNotOnSessionDate
    case sessionDurationTooShort(minimum: TimeInterval)
    case sessionDurationTooLong(maximum: TimeInterval)
    case invalidURL(String)
    case missingFacebookPageName
}
