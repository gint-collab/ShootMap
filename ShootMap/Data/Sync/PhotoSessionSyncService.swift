//
//  PhotoSessionSyncService.swift
//  ShootMap
//
//  Created by Septuagint Murito on 8/17/26.
//

import Foundation

/// Outcome of a single reconciliation pass. Returned rather than logged so
/// callers (and tests) can assert on what actually changed.
nonisolated struct PhotoSessionSyncReport: Hashable, Sendable {
    var inserted: Int = 0
    var updated: Int = 0
    var removed: Int = 0
    var syncedAt: Date = .now

    var didChangeAnything: Bool { inserted > 0 || updated > 0 || removed > 0 }
}

/// Reconciles the Firestore source of truth with the SwiftData cache.
///
/// The only session collaborator ViewModels see, so no ViewModel ever decides
/// between "remote" and "local". It names neither concrete repository, imports
/// neither Firebase nor SwiftData, and contains no SwiftUI — it depends purely
/// on `PhotoSessionRepositoryProtocol` and `LocalPhotoSessionRepositoryProtocol`.
nonisolated final class PhotoSessionSyncService: PhotoSessionSyncServiceProtocol {

    private let remote: any PhotoSessionRepositoryProtocol
    private let local: any LocalPhotoSessionRepositoryProtocol

    /// Retention rules for the local cache. Injected so the app, tests and debug
    /// builds can choose different windows without changing this type.
    private let retentionPolicy: CacheRetentionPolicy

    init(
        remote: any PhotoSessionRepositoryProtocol,
        local: any LocalPhotoSessionRepositoryProtocol,
        retentionPolicy: CacheRetentionPolicy = .default
    ) {
        self.remote = remote
        self.local = local
        self.retentionPolicy = retentionPolicy
    }

    // MARK: - Cache-first reads

    func sessions(matching query: PhotoSessionQuery) -> AsyncThrowingStream<PhotoSessionSnapshot, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                // 1. Serve the cache immediately so the map is never blank while
                //    the network is in flight. An empty cache yields nothing
                //    rather than a misleading "no sessions" snapshot.
                if let cached = try? await local.sessions(matching: query), !cached.isEmpty {
                    let syncedAt = try? await local.lastSyncedAt()
                    continuation.yield(
                        PhotoSessionSnapshot(sessions: cached, origin: .cache, syncedAt: syncedAt)
                    )
                }

                // 2. Then follow live remote updates, reconciling the cache as
                //    each snapshot arrives.
                do {
                    for try await sessions in remote.sessionUpdates(matching: query) {
                        try Task.checkCancellation()

                        // A cache write failure must not tear down a working
                        // stream — the remote data is still valid to display.
                        let report = try? await reconcile(
                            remoteSessions: sessions,
                            matching: query
                        )

                        continuation.yield(
                            PhotoSessionSnapshot(
                                sessions: sessions,
                                origin: .remote,
                                syncedAt: report?.syncedAt ?? .now
                            )
                        )
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    // The cached snapshot was already delivered and is left
                    // untouched, so the UI can show stale data alongside the error.
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Explicit refresh

    @discardableResult
    func refresh(matching query: PhotoSessionQuery) async throws -> [PhotoSession] {
        // If this throws, nothing below runs — the cache survives a network
        // failure completely intact.
        let sessions = try await remote.sessions(matching: query)
        try await reconcile(remoteSessions: sessions, matching: query)
        return sessions
    }

    /// Same as `refresh`, but reports what changed.
    @discardableResult
    func synchronize(matching query: PhotoSessionQuery) async throws -> PhotoSessionSyncReport {
        let sessions = try await remote.sessions(matching: query)
        return try await reconcile(remoteSessions: sessions, matching: query)
    }

    // MARK: - Reconciliation

    /// Three-way merge of a remote result set into the cache.
    ///
    /// - Inserts sessions the cache has never seen.
    /// - Updates rows whose remote copy differs (unchanged rows are skipped, so
    ///   a no-op sync performs no writes).
    /// - Removes rows that matched `query` locally but are absent remotely —
    ///   i.e. deleted, or cancelled out of a status-filtered query.
    ///
    /// - Important: deletion is scoped to `query`. A map-region or
    ///   photographer-scoped sync therefore cannot evict cached rows that simply
    ///   fall outside the window it asked about.
    @discardableResult
    private func reconcile(
        remoteSessions: [PhotoSession],
        matching query: PhotoSessionQuery,
        syncedAt: Date = .now
    ) async throws -> PhotoSessionSyncReport {
        var report = PhotoSessionSyncReport(syncedAt: syncedAt)

        // A limited query returns a window, not the full truth for its scope, so
        // absence from the result set does not imply remote deletion.
        let cached = query.limit == nil
            ? try await local.sessions(matching: query)
            : []

        let cachedById = Dictionary(cached.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let remoteIds = Set(remoteSessions.map(\.id))

        // Insert + update, skipping rows that are already identical.
        var changed: [PhotoSession] = []
        for session in remoteSessions {
            if let existing = cachedById[session.id] {
                guard existing != session else { continue }
                report.updated += 1
            } else {
                report.inserted += 1
            }
            changed.append(session)
        }

        if !changed.isEmpty {
            try await local.upsert(changed, syncedAt: syncedAt)
        }

        // Removed / cancelled: present locally for this query, gone remotely.
        let staleIds = cached.map(\.id).filter { !remoteIds.contains($0) }
        if !staleIds.isEmpty {
            try await local.delete(sessionIds: staleIds)
            report.removed = staleIds.count
        }

        return report
    }

    // MARK: - Writes (write-through: remote first, then cache)

    @discardableResult
    func publish(_ session: PhotoSession) async throws -> PhotoSession {
        // Remote first: the cache must never contain a session the server
        // rejected, so a failed publish leaves no local trace.
        let stored = try await remote.publish(session)
        try? await local.upsert([stored], syncedAt: .now)
        return stored
    }

    @discardableResult
    func update(_ session: PhotoSession) async throws -> PhotoSession {
        let stored = try await remote.update(session)
        try? await local.upsert([stored], syncedAt: .now)
        return stored
    }

    /// Cancelled sessions are **updated, not deleted**, so a viewer with the
    /// detail screen open sees the cancellation rather than an empty screen.
    /// They also remain on the map — viewers browse every status — until the
    /// retention policy eventually evicts them.
    func cancel(sessionId id: String) async throws {
        try await remote.updateStatus(.cancelled, forSessionId: id)

        if let cached = try? await local.session(id: id),
           let cancelled = cached.transitioned(to: .cancelled) {
            try? await local.upsert([cancelled], syncedAt: .now)
        }
    }

    func delete(sessionId id: String) async throws {
        try await remote.delete(sessionId: id)
        try? await local.delete(sessionIds: [id])
    }

    // MARK: - Cache lifecycle

    func invalidateCache() async throws {
        try await local.clear()
    }

    /// Evicts sessions that ended before `date`. Worth calling at launch so the
    /// cache does not grow without bound.
    func purgeExpired(before date: Date = .now) async throws {
        try await local.purgeSessions(endedBefore: date)
    }

    /// Applies the cache retention policy.
    ///
    /// Safe to call at launch and on returning to the foreground: it only ever
    /// removes sessions that have already ended *and* outlived their status's
    /// retention window, so today's and all future sessions are untouched.
    ///
    /// Failure is deliberately swallowed by callers that treat this as
    /// housekeeping — a cache that failed to shrink is not a user-facing problem.
    func cleanUpCache(
        policy: CacheRetentionPolicy? = nil,
        now: Date = .now
    ) async throws {
        try await local.applyRetentionPolicy(policy ?? retentionPolicy, now: now)
    }
}
