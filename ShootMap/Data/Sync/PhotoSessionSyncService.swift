//
//  PhotoSessionSyncService.swift
//  ShootMap
//
//  Created by Septuagint Murito on 8/17/26.
//

import Foundation

/// Reconciles the Firestore source of truth with the SwiftData cache.
///
/// The only session collaborator ViewModels see, so no ViewModel ever decides
/// between "remote" and "local". Neither repository type is named in its API.
nonisolated final class PhotoSessionSyncService: PhotoSessionSyncServiceProtocol {

    private let remote: any PhotoSessionRepositoryProtocol
    private let local: any LocalPhotoSessionRepositoryProtocol

    init(
        remote: any PhotoSessionRepositoryProtocol,
        local: any LocalPhotoSessionRepositoryProtocol
    ) {
        self.remote = remote
        self.local = local
    }

    // MARK: Cache-first reads

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

                // 2. Then follow live remote updates, refreshing the cache as
                //    each snapshot arrives.
                do {
                    for try await sessions in remote.sessionUpdates(matching: query) {
                        try Task.checkCancellation()
                        let syncedAt = Date.now
                        try? await local.upsert(sessions, syncedAt: syncedAt)
                        continuation.yield(
                            PhotoSessionSnapshot(sessions: sessions, origin: .remote, syncedAt: syncedAt)
                        )
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    // The cached snapshot has already been delivered, so the UI
                    // can choose to show stale data alongside the error.
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Explicit refresh

    @discardableResult
    func refresh(matching query: PhotoSessionQuery) async throws -> [PhotoSession] {
        let sessions = try await remote.sessions(matching: query)
        try await local.upsert(sessions, syncedAt: .now)
        return sessions
    }

    // MARK: Writes

    @discardableResult
    func publish(_ session: PhotoSession) async throws -> PhotoSession {
        // Remote first: the cache must never contain a session the server
        // rejected, so a failed publish leaves no local trace.
        let stored = try await remote.publish(session)
        try await local.upsert([stored], syncedAt: .now)
        return stored
    }

    // MARK: Cache lifecycle

    func invalidateCache() async throws {
        try await local.clear()
    }
}
