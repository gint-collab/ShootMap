//
//  User.swift
//  ShootMap
//
//  Created by Septuagint Murito on 8/15/26.
//

import Foundation

/// An application user. Pure value type — no Firebase, no SwiftData, no UI.
/// `nonisolated` because the module opts into default main-actor isolation;
/// domain models must stay actor-agnostic and `Sendable`.
nonisolated struct User: DomainEntity, SocialPagePresentable {
    let id: String
    let email: String
    let displayName: String
    let facebookPageName: String?
    let facebookPageURL: URL?
    let role: UserRole
    let createdAt: Date

    init(
        id: String,
        email: String,
        displayName: String,
        facebookPageName: String? = nil,
        facebookPageURL: URL? = nil,
        role: UserRole = .client,
        createdAt: Date = .now
    ) {
        self.id = id
        self.email = email.trimmed.lowercased()
        self.displayName = displayName.trimmed
        self.facebookPageName = facebookPageName?.trimmedNonEmpty
        self.facebookPageURL = facebookPageURL
        self.role = role
        self.createdAt = createdAt
    }
}

// MARK: - Validation

nonisolated extension User: Validatable {
    func validate() throws {
        guard !id.trimmed.isEmpty else { throw DomainValidationError.emptyIdentifier }
        guard !displayName.isEmpty else { throw DomainValidationError.emptyDisplayName }
        guard EmailFormat.isValid(email) else { throw DomainValidationError.invalidEmail(email) }

        if role.requiresFacebookPage, facebookPageName == nil, facebookPageURL == nil {
            throw DomainValidationError.missingFacebookPageName
        }
    }
}

// MARK: - Behaviour

nonisolated extension User {
    var canPublishSessions: Bool { role.canPublishSessions }

    var hasSocialPage: Bool { facebookPageName != nil || facebookPageURL != nil }

    /// Non-mutating copy helpers keep the type immutable while staying ergonomic.
    func withRole(_ newRole: UserRole) -> User {
        User(
            id: id,
            email: email,
            displayName: displayName,
            facebookPageName: facebookPageName,
            facebookPageURL: facebookPageURL,
            role: newRole,
            createdAt: createdAt
        )
    }

    func withSocialPage(name: String?, url: URL?) -> User {
        User(
            id: id,
            email: email,
            displayName: displayName,
            facebookPageName: name,
            facebookPageURL: url,
            role: role,
            createdAt: createdAt
        )
    }
}

// MARK: - Helpers

nonisolated enum EmailFormat {
    /// Intentionally conservative; the authoritative check belongs to the auth provider.
    static func isValid(_ value: String) -> Bool {
        let candidate = value.trimmed
        guard !candidate.isEmpty, !candidate.contains(" ") else { return false }
        let parts = candidate.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return false }
        let domain = parts[1]
        guard domain.contains("."), !domain.hasPrefix("."), !domain.hasSuffix(".") else { return false }
        return true
    }
}
