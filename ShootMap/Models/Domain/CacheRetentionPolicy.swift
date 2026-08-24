//
//  CacheRetentionPolicy.swift
//  ShootMap
//
//  Created by Septuagint Murito on 8/19/26.
//

import Foundation

/// How long finished sessions are kept in the local cache.
///
/// A value type with no dependencies, so the rules are stated in one place and
/// can be swapped wholesale (tests, debug builds, remote config) without
/// touching the repository.
///
/// Retention is always measured from a session's **`endTime`**, never `date` or
/// `createdAt`. That is what guarantees the two safety invariants:
///
/// - Sessions still running or yet to happen have an `endTime` in the future, so
///   no cutoff can ever match them.
/// - Today's sessions are only eligible once they have ended *and* outlived
///   their status's retention period — which is at minimum a day.
nonisolated struct CacheRetentionPolicy: Hashable, Sendable {

    /// How long a `completed` session is kept after it ends.
    var completedRetention: TimeInterval

    /// How long a `cancelled` session is kept after its scheduled end.
    var cancelledRetention: TimeInterval

    /// How long a session still marked `scheduled` or `ongoing` is kept after it
    /// should have finished.
    ///
    /// These are sessions the photographer never closed out. They are kept
    /// generously, because they may still be reconciled to a real status by a
    /// later sync — but not forever, or the cache would grow without bound.
    var stalePeriod: TimeInterval

    init(
        completedRetention: TimeInterval = .days(30),
        cancelledRetention: TimeInterval = .days(7),
        stalePeriod: TimeInterval = .days(30)
    ) {
        self.completedRetention = completedRetention
        self.cancelledRetention = cancelledRetention
        self.stalePeriod = stalePeriod
    }

    /// The shipping policy: completed kept 30 days, cancelled 7.
    static let `default` = CacheRetentionPolicy()

    /// Keeps everything. Useful for debugging or offline-heavy scenarios.
    static let unlimited = CacheRetentionPolicy(
        completedRetention: .infinity,
        cancelledRetention: .infinity,
        stalePeriod: .infinity
    )

    // MARK: - Cutoffs

    /// The `endTime` before which a session of this status may be evicted.
    /// `nil` means "never evict this status".
    func cutoff(for status: SessionStatus, now: Date = .now) -> Date? {
        let retention: TimeInterval = switch status {
        case .completed: completedRetention
        case .cancelled: cancelledRetention
        case .scheduled, .ongoing: stalePeriod
        }

        guard retention.isFinite else { return nil }

        // Subtracting from `now` means the cutoff is always in the past, so a
        // future session can never fall before it. This is the mechanism that
        // enforces "never remove future scheduled sessions".
        return now.addingTimeInterval(-retention)
    }

    /// Whether a specific session is eligible for eviction.
    /// Exposed so callers can reason about a single record without a store round trip.
    func isExpired(_ session: PhotoSession, now: Date = .now) -> Bool {
        guard let cutoff = cutoff(for: session.status, now: now) else { return false }
        return session.endTime < cutoff
    }

    /// Every status paired with its cutoff, skipping those kept indefinitely.
    func cutoffs(now: Date = .now) -> [(status: SessionStatus, cutoff: Date)] {
        SessionStatus.allCases.compactMap { status in
            cutoff(for: status, now: now).map { (status, $0) }
        }
    }
}

// MARK: - Readability

nonisolated extension TimeInterval {
    static func days(_ count: Double) -> TimeInterval { count * 86_400 }
    static func hours(_ count: Double) -> TimeInterval { count * 3_600 }
}
