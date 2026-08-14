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
