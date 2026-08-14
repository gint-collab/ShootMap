//
//  UserRole.swift
//  ShootMap
//
//  Created by Septuagint Murito on 8/15/26.
//

import Foundation

/// Role assigned to a `User`. Raw values are the persistence contract.
nonisolated enum UserRole: String, CaseIterable, Hashable, Sendable, Codable {
    case photographer
    case client
    case admin

    /// Only photographers publish sessions onto the map.
    var canPublishSessions: Bool {
        switch self {
        case .photographer, .admin: true
        case .client: false
        }
    }

    var canModerateSessions: Bool { self == .admin }

    /// A Facebook page is part of a photographer's public profile.
    var requiresFacebookPage: Bool { self == .photographer }
}

nonisolated extension UserRole {
    /// Forward-compatible decoding: unknown roles degrade to the least-privileged role.
    init(storedValue: String?) {
        self = UserRole(rawValue: storedValue ?? "") ?? .client
    }
}
