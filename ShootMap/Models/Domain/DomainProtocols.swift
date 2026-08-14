//
//  DomainProtocols.swift
//  ShootMap
//
//  Created by Septuagint Murito on 8/15/26.
//

import Foundation

/// A domain entity that has a stable identity and is safe to pass across concurrency domains.
nonisolated protocol DomainEntity: Identifiable, Hashable, Sendable, Codable {
    associatedtype Identifier: Hashable & Sendable & Codable
    var id: Identifier { get }
    var createdAt: Date { get }
}

/// A value type that can assert its own invariants without any external dependency.
nonisolated protocol Validatable {
    func validate() throws
}

nonisolated extension Validatable {
    var isValid: Bool {
        (try? validate()) != nil
    }
}

/// Anything that can be placed on the map.
nonisolated protocol GeoLocatable {
    var coordinate: Coordinate { get }
}

/// Anything that occupies a time range on a given calendar day.
nonisolated protocol TimeBounded {
    var date: Date { get }
    var startTime: Date { get }
    var endTime: Date { get }
}

nonisolated extension TimeBounded {
    var duration: TimeInterval { endTime.timeIntervalSince(startTime) }

    func overlaps(_ other: some TimeBounded) -> Bool {
        startTime < other.endTime && other.startTime < endTime
    }

    func contains(_ instant: Date) -> Bool {
        instant >= startTime && instant <= endTime
    }
}

/// A public-facing social page reference.
nonisolated protocol SocialPagePresentable {
    var facebookPageName: String? { get }
    var facebookPageURL: URL? { get }
}
