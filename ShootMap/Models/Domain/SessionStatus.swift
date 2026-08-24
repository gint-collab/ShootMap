//
//  SessionStatus.swift
//  ShootMap
//
//  Created by Septuagint Murito on 8/15/26.
//

import Foundation

/// Lifecycle state of a `PhotoSession`. Raw values are the persistence contract.
nonisolated enum SessionStatus: String, CaseIterable, Hashable, Sendable, Codable {
    case scheduled
    case ongoing
    case completed
    case cancelled

    var isActive: Bool {
        self == .scheduled || self == .ongoing
    }

    var isTerminal: Bool { !isActive }

    /// Encapsulates the legal state machine transitions.
    func canTransition(to next: SessionStatus) -> Bool {
        switch (self, next) {
        case (.scheduled, .ongoing),
             (.scheduled, .cancelled),
             (.ongoing, .completed),
             (.ongoing, .cancelled):
            true
        default:
            false
        }
    }

    /// Derives the status implied by a time range, ignoring manual cancellation.
    static func derived(from bounds: some TimeBounded, now: Date = .now) -> SessionStatus {
        if now < bounds.startTime { return .scheduled }
        if now > bounds.endTime { return .completed }
        return .ongoing
    }
}

nonisolated extension SessionStatus {
    init(storedValue: String?) {
        self = SessionStatus(rawValue: storedValue ?? "") ?? .scheduled
    }
}
