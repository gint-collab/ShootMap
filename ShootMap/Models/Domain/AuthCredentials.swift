//
//  AuthCredentials.swift
//  ShootMap
//
//  Created by Septuagint Murito on 8/15/26.
//

import Foundation

/// Sign-in input. A plain value type so nothing in the app layer
/// needs to know which auth provider is behind the repository.
nonisolated struct SignInCredentials: Hashable, Sendable {
    let email: String
    let password: String

    init(email: String, password: String) {
        self.email = email.trimmed.lowercased()
        self.password = password
    }
}

/// Sign-up input, including the profile fields captured during registration.
nonisolated struct SignUpRequest: Hashable, Sendable {
    let email: String
    let password: String
    let displayName: String
    let role: UserRole
    let facebookPageName: String?
    let facebookPageURL: URL?

    init(
        email: String,
        password: String,
        displayName: String,
        role: UserRole,
        facebookPageName: String? = nil,
        facebookPageURL: URL? = nil
    ) {
        self.email = email.trimmed.lowercased()
        self.password = password
        self.displayName = displayName.trimmed
        self.role = role
        self.facebookPageName = facebookPageName?.trimmedNonEmpty
        self.facebookPageURL = facebookPageURL
    }
}
