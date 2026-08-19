//
//  LocalPhotoSessionRepositoryProtocol.swift
//  ShootMap
//
//  Created by Septuagint Murito on 8/15/26.
//

import Foundation

/// The local cache surface. SwiftData is the implementation detail —
/// no `ModelContext`, `ModelContainer`, or `PhotoSessionEntity` crosses this boundary.
///
/// Deliberately mirrors the remote read API so the sync service can treat both
/// sides uniformly, plus cache-specific maintenance operations.
nonisolated protocol LocalPhotoSessionRepositoryProtocol: Sendable {

    // MARK: Read

    func sessions(matching query: PhotoSessionQuery) async throws -> [PhotoSession]
    func session(id: String) async throws -> PhotoSession?

    // MARK: Write

    /// Inserts or updates the given sessions, stamping each with `syncedAt`.
    /// Must be idempotent — replaying the same batch changes nothing.
    func upsert(_ sessions: [PhotoSession], syncedAt: Date) async throws

    func delete(sessionIds ids: [String]) async throws

    /// Removes every cached row. Used on sign-out.
    func clear() async throws

    // MARK: Cache maintenance

    /// Most recent successful sync stamp, or `nil` if the cache was never filled.
    func lastSyncedAt() async throws -> Date?

    /// Evicts rows whose sessions ended before `date`.
    func purgeSessions(endedBefore date: Date) async throws

    /// Evicts rows with the given status whose sessions ended before `date`.
    /// The primitive the retention policy is built on — status-aware so
    /// completed and cancelled sessions can age out at different rates.
    func purgeSessions(withStatus status: SessionStatus, endedBefore date: Date) async throws
}

// MARK: - Retention

nonisolated extension LocalPhotoSessionRepositoryProtocol {

    /// Applies a retention policy to the cache.
    ///
    /// Lives here, in the repository layer, so no ViewModel or coordinator ever
    /// decides what to evict. Sessions that are ongoing or in the future have an
    /// `endTime` later than every cutoff, so they are structurally unreachable
    /// by this — "never remove future scheduled sessions" is a property of the
    /// query, not a special case.
    func applyRetentionPolicy(
        _ policy: CacheRetentionPolicy = .default,
        now: Date = .now
    ) async throws {
        for (status, cutoff) in policy.cutoffs(now: now) {
            try await purgeSessions(withStatus: status, endedBefore: cutoff)
        }
    }
}

// MARK: - Convenience

nonisolated extension LocalPhotoSessionRepositoryProtocol {
    func upsert(_ sessions: [PhotoSession]) async throws {
        try await upsert(sessions, syncedAt: .now)
    }

    func delete(sessionId id: String) async throws {
        try await delete(sessionIds: [id])
    }
}
