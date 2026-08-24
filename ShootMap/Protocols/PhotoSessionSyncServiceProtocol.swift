//
//  PhotoSessionSyncServiceProtocol.swift
//  ShootMap
//
//  Created by Septuagint Murito on 8/15/26.
//

import Foundation

/// Where a set of sessions came from, so the UI can distinguish
/// "cached, possibly stale" from "fresh from the server".
nonisolated enum DataOrigin: Hashable, Sendable {
    case cache
    case remote
}

/// A batch of sessions plus its provenance.
nonisolated struct PhotoSessionSnapshot: Hashable, Sendable {
    let sessions: [PhotoSession]
    let origin: DataOrigin
    let syncedAt: Date?

    init(sessions: [PhotoSession], origin: DataOrigin, syncedAt: Date? = nil) {
        self.sessions = sessions
        self.origin = origin
        self.syncedAt = syncedAt
    }
}

/// Coordinates the remote source of truth with the local cache.
///
/// This is the single collaborator ViewModels talk to for session data — they
/// never choose between "remote" and "local" themselves.
nonisolated protocol PhotoSessionSyncServiceProtocol: Sendable {

    /// Cache-first read: yields the cached snapshot immediately (if any),
    /// then a remote snapshot once reconciliation completes.
    func sessions(matching query: PhotoSessionQuery) -> AsyncThrowingStream<PhotoSessionSnapshot, Error>

    /// Forces a reconciliation pass and returns the freshly synced sessions.
    @discardableResult
    func refresh(matching query: PhotoSessionQuery) async throws -> [PhotoSession]

    /// Publishes a new session remotely and reflects it in the cache.
    @discardableResult
    func publish(_ session: PhotoSession) async throws -> PhotoSession

    /// Drops all locally cached data. Used on sign-out.
    func invalidateCache() async throws
}
