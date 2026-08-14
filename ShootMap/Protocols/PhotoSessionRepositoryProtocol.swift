//
//  PhotoSessionRepositoryProtocol.swift
//  ShootMap
//
//  Created by Septuagint Murito on 8/15/26.
//

import Foundation

// MARK: - Segregated roles

/// Reads sessions from the remote source of truth.
nonisolated protocol PhotoSessionReading: Sendable {
    func sessions(matching query: PhotoSessionQuery) async throws -> [PhotoSession]
    func session(id: String) async throws -> PhotoSession?
}

/// Publishes and mutates sessions. Only photographer-facing features need this.
nonisolated protocol PhotoSessionWriting: Sendable {
    /// Creates the session remotely and returns the stored value
    /// (which may carry a server-assigned id or timestamp).
    @discardableResult
    func publish(_ session: PhotoSession) async throws -> PhotoSession

    @discardableResult
    func update(_ session: PhotoSession) async throws -> PhotoSession

    func updateStatus(_ status: SessionStatus, forSessionId id: String) async throws

    func delete(sessionId id: String) async throws
}

/// Live updates from the remote source of truth, surfaced as an async sequence
/// so callers never see a snapshot listener or a completion handler.
nonisolated protocol PhotoSessionObserving: Sendable {
    func sessionUpdates(matching query: PhotoSessionQuery) -> AsyncThrowingStream<[PhotoSession], Error>
}

// MARK: - Composed facade

/// Remote session repository. Firestore is the implementation detail;
/// nothing here exposes it.
nonisolated protocol PhotoSessionRepositoryProtocol: PhotoSessionReading, PhotoSessionWriting, PhotoSessionObserving {}
