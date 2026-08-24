//
//  FirestorePhotoSessionRepository.swift
//  ShootMap
//
//  Created by Septuagint Murito on 8/17/26.
//

import Foundation
// `@preconcurrency`: `Firestore` is thread-safe but not annotated `Sendable`,
// which is an error under the Swift 6 language mode.
@preconcurrency import FirebaseFirestore

/// Firestore-backed remote source of truth for photo sessions.
///
/// Reads and writes the `photoSessions` collection, converting documents to
/// domain `PhotoSession` values and provider failures to `PhotoSessionError`.
/// No Firestore type appears in any signature, and SwiftData is never involved —
/// caching is the sync service's job.
///
/// Ownership is enforced here: writes are stamped with, and checked against, the
/// authenticated photographer's id obtained through `AuthSessionProviding`.
nonisolated final class FirestorePhotoSessionRepository: PhotoSessionRepositoryProtocol {

    private let firestore: Firestore

    /// Supplies the authenticated user. Protocol-typed, so this repository never
    /// touches FirebaseAuth and can be exercised with a stubbed session.
    private let sessionProvider: any AuthSessionProviding

    init(
        firestore: Firestore,
        sessionProvider: any AuthSessionProviding
    ) {
        self.firestore = firestore
        self.sessionProvider = sessionProvider
    }

    private var collection: CollectionReference {
        firestore.collection(FirestoreCollection.photoSessions)
    }

    // MARK: - Create

    /// Publishes a new session owned by the signed-in photographer.
    ///
    /// The caller's `photographerId` is ignored and replaced with the
    /// authenticated id, so a client cannot publish a session attributed to
    /// someone else.
    @discardableResult
    func createSession(_ session: PhotoSession) async throws -> PhotoSession {
        let author = try await authenticatedPublisher()
        let owned = session.ownedBy(author)

        do {
            try owned.validate()
        } catch let error as DomainValidationError {
            throw PhotoSessionError.invalid(error)
        }

        try await mapErrors {
            // `setData` rather than `addDocument`: the domain owns the id, which
            // keeps local and remote records addressable by the same key.
            try await collection.document(owned.id).setData(owned.firestoreData)
        }
        return owned
    }

    // MARK: - Read

    /// Every session, ordered by the query's default (start time ascending).
    func fetchSessions() async throws -> [PhotoSession] {
        try await sessions(matching: PhotoSessionQuery())
    }

    /// Sessions whose start time falls on `date`, in the given calendar's day.
    func fetchSessions(for date: Date, calendar: Calendar = .current) async throws -> [PhotoSession] {
        let start = calendar.startOfDay(for: date)
        guard let next = calendar.date(byAdding: .day, value: 1, to: start) else {
            return []
        }
        // Upper bound nudged back so a session starting exactly at midnight
        // belongs to the following day only, never to both.
        let range = start...next.addingTimeInterval(-0.001)
        return try await sessions(matching: PhotoSessionQuery(dateRange: range))
    }

    /// A photographer's own sessions, newest first.
    func fetchSessions(authoredBy photographerId: String) async throws -> [PhotoSession] {
        try await sessions(matching: .authored(by: photographerId))
    }

    func sessions(matching query: PhotoSessionQuery) async throws -> [PhotoSession] {
        let snapshot = try await mapErrors {
            try await makeQuery(from: query).getDocuments()
        }
        return query.apply(to: Self.decode(snapshot))
    }

    func session(id: String) async throws -> PhotoSession? {
        let document = try await mapErrors {
            try await collection.document(id).getDocument()
        }
        guard document.exists else { return nil }
        do {
            return try PhotoSession(snapshot: document)
        } catch {
            throw PhotoSessionError.malformedSession(id: id)
        }
    }

    // MARK: - Update

    /// Updates a session the signed-in photographer owns.
    @discardableResult
    func updateSession(_ session: PhotoSession) async throws -> PhotoSession {
        let author = try await authenticatedPublisher()
        try await assertOwnership(ofSessionId: session.id, by: author.id)

        let owned = session.ownedBy(author)
        do {
            try owned.validate()
        } catch let error as DomainValidationError {
            throw PhotoSessionError.invalid(error)
        }

        try await mapErrors {
            // `merge` so a partial write never erases fields added by a newer
            // client version.
            try await collection.document(owned.id).setData(owned.firestoreData, merge: true)
        }
        return owned
    }

    func updateStatus(_ status: SessionStatus, forSessionId id: String) async throws {
        let author = try await authenticatedPublisher()
        try await assertOwnership(ofSessionId: id, by: author.id)

        try await mapErrors {
            try await collection.document(id).updateData([SessionField.status: status.rawValue])
        }
    }

    // MARK: - Delete

    func deleteSession(id: String) async throws {
        let author = try await authenticatedPublisher()
        try await assertOwnership(ofSessionId: id, by: author.id)

        try await mapErrors {
            try await collection.document(id).delete()
        }
    }

    // MARK: - Observe

    func sessionUpdates(matching query: PhotoSessionQuery) -> AsyncThrowingStream<[PhotoSession], Error> {
        AsyncThrowingStream { continuation in
            let registration = makeQuery(from: query).addSnapshotListener { snapshot, error in
                if let error {
                    continuation.finish(throwing: PhotoSessionError(error))
                    return
                }
                guard let snapshot else { return }
                continuation.yield(query.apply(to: Self.decode(snapshot)))
            }
            // Detaching on termination is what makes task cancellation actually
            // stop the listener rather than leak it for the app's lifetime.
            continuation.onTermination = { _ in registration.remove() }
        }
    }

    // MARK: - Protocol conformance
    //
    // `PhotoSessionRepositoryProtocol` uses publish/update/delete naming; these
    // forward to the methods above so there is only one implementation of each.

    @discardableResult
    func publish(_ session: PhotoSession) async throws -> PhotoSession {
        try await createSession(session)
    }

    @discardableResult
    func update(_ session: PhotoSession) async throws -> PhotoSession {
        try await updateSession(session)
    }

    func delete(sessionId id: String) async throws {
        try await deleteSession(id: id)
    }

    // MARK: - Ownership

    /// The signed-in user, confirmed to be allowed to publish.
    private func authenticatedPublisher() async throws -> User {
        guard let user = await sessionProvider.currentUser() else {
            throw PhotoSessionError.notAuthenticated
        }
        guard user.canPublishSessions else {
            throw PhotoSessionError.notPermittedToPublish
        }
        return user
    }

    /// Fails unless `photographerId` authored the stored session.
    ///
    /// This is a usability guard, not the security boundary — a determined
    /// client can call Firestore directly. Firestore security rules must enforce
    /// the same rule server-side.
    private func assertOwnership(ofSessionId id: String, by photographerId: String) async throws {
        let document = try await mapErrors {
            try await collection.document(id).getDocument()
        }
        guard let data = document.data() else {
            throw PhotoSessionError.sessionNotFound(id: id)
        }
        guard data[SessionField.photographerId] as? String == photographerId else {
            throw PhotoSessionError.notSessionOwner
        }
    }

    // MARK: - Query building

    /// Pushes down only the filters Firestore can serve without a composite index.
    ///
    /// A viewport is deliberately **not** translated into `latitude`/`longitude`
    /// range filters: combining those with a `startTime` range requires a
    /// composite index and still cannot express a true bounding box. The region
    /// is applied in memory by `PhotoSessionQuery.apply(to:)`.
    private func makeQuery(from query: PhotoSessionQuery) -> Query {
        var result: Query = collection

        if let photographerId = query.photographerId {
            result = result.whereField(SessionField.photographerId, isEqualTo: photographerId)
        }
        // Firestore caps `in` at 30 values; the enum has four, so this is safe.
        if !query.statuses.isEmpty {
            result = result.whereField(SessionField.status, in: query.statuses.map(\.rawValue))
        }
        if let dateRange = query.dateRange {
            result = result
                .whereField(SessionField.startTime, isGreaterThanOrEqualTo: Timestamp(date: dateRange.lowerBound))
                .whereField(SessionField.startTime, isLessThanOrEqualTo: Timestamp(date: dateRange.upperBound))
        }
        return result
    }

    /// Skips unreadable documents rather than failing the whole batch — one bad
    /// row written by a future client version should not blank the map.
    private static func decode(_ snapshot: QuerySnapshot) -> [PhotoSession] {
        snapshot.documents.compactMap { try? PhotoSession(snapshot: $0) }
    }

    // MARK: - Error translation

    private func mapErrors<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch let error as PhotoSessionError {
            throw error
        } catch {
            throw PhotoSessionError(error)
        }
    }
}

// MARK: - Ownership stamping

private extension PhotoSession {
    /// Returns a copy attributed to `author`, carrying their current profile
    /// details so the session snapshot survives later profile edits.
    func ownedBy(_ author: User) -> PhotoSession {
        PhotoSession(
            id: id,
            photographerId: author.id,
            photographerName: author.displayName,
            facebookPageName: author.facebookPageName,
            facebookPageURL: author.facebookPageURL,
            latitude: latitude,
            longitude: longitude,
            date: date,
            startTime: startTime,
            endTime: endTime,
            createdAt: createdAt,
            status: status
        )
    }
}

// MARK: - Firestore error translation

private extension PhotoSessionError {

    /// Maps a Firestore error onto the application's error model.
    /// Confined to this file so `FirestoreErrorCode` appears nowhere else.
    init(_ error: Error) {
        let nsError = error as NSError

        guard nsError.domain == FirestoreErrorDomain,
              let code = FirestoreErrorCode.Code(rawValue: nsError.code) else {
            self = .unknown(message: nsError.localizedDescription)
            return
        }

        switch code {
        case .unavailable, .deadlineExceeded:
            self = .networkUnavailable
        case .permissionDenied, .unauthenticated:
            self = .permissionDenied
        case .resourceExhausted:
            self = .quotaExceeded
        case .dataLoss, .invalidArgument:
            self = .malformedSession(id: "")
        default:
            self = .unknown(message: nsError.localizedDescription)
        }
    }
}
