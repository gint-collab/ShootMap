//
//  Mocks.swift
//  ShootMapTests
//
//  Protocol-based test doubles. Nothing here touches Firebase, the network,
//  or the on-disk store — every dependency is satisfied by an in-memory stub.
//

import Foundation
@testable import ShootMap

// MARK: - Fixtures

enum Fixture {

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// A fixed "now" so every date assertion is deterministic.
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    static func photographer(
        id: String = "photographer-1",
        name: String = "Ansel",
        page: String? = "anselpage"
    ) -> User {
        User(
            id: id,
            email: "ansel@example.com",
            displayName: name,
            facebookPageName: page,
            facebookPageURL: URL(string: "https://facebook.com/anselpage"),
            role: .photographer,
            createdAt: now
        )
    }

    static func viewer(id: String = "viewer-1") -> User {
        User(
            id: id,
            email: "viewer@example.com",
            displayName: "Vera",
            role: .client,
            createdAt: now
        )
    }

    /// A valid session on the day containing `start`.
    static func session(
        id: String = "session-1",
        photographerId: String = "photographer-1",
        photographerName: String = "Ansel",
        start: Date = now.addingTimeInterval(3_600),
        duration: TimeInterval = 3_600,
        latitude: Double = 14.5995,
        longitude: Double = 120.9842,
        status: SessionStatus = .scheduled
    ) -> PhotoSession {
        PhotoSession(
            id: id,
            photographerId: photographerId,
            photographerName: photographerName,
            facebookPageName: "anselpage",
            facebookPageURL: URL(string: "https://facebook.com/anselpage"),
            latitude: latitude,
            longitude: longitude,
            date: calendar.startOfDay(for: start),
            startTime: start,
            endTime: start.addingTimeInterval(duration),
            createdAt: now,
            status: status
        )
    }

    static let manila = CoordinateRegion(
        center: try! Coordinate(latitude: 14.5995, longitude: 120.9842),
        latitudeDelta: 0.5,
        longitudeDelta: 0.5
    )
}

// MARK: - Errors

enum TestError: Error, Equatable, LocalizedError {
    case network
    case cache

    var errorDescription: String? {
        switch self {
        case .network: "Simulated network failure."
        case .cache: "Simulated cache failure."
        }
    }
}

// MARK: - Auth

/// In-memory `AuthRepositoryProtocol`. `@unchecked Sendable` because access is
/// serialised by the test's single-threaded use, not by a lock.
final class MockAuthRepository: AuthRepositoryProtocol, @unchecked Sendable {

    var signInResult: Result<User, Error> = .success(Fixture.viewer())
    var signUpResult: Result<User, Error> = .success(Fixture.viewer())
    var storedUser: User?

    private(set) var signInCallCount = 0
    private(set) var signOutCallCount = 0
    private(set) var lastCredentials: SignInCredentials?

    private let continuationBox = ContinuationBox()

    func currentUser() async -> User? { storedUser }

    var authStateUpdates: AsyncStream<User?> {
        AsyncStream { continuation in
            continuationBox.continuation = continuation
            continuation.yield(storedUser)
        }
    }

    /// Pushes a new auth state to observers.
    func emit(_ user: User?) {
        storedUser = user
        continuationBox.continuation?.yield(user)
    }

    @discardableResult
    func signIn(with credentials: SignInCredentials) async throws -> User {
        signInCallCount += 1
        lastCredentials = credentials
        let user = try signInResult.get()
        storedUser = user
        return user
    }

    @discardableResult
    func signUp(with request: SignUpRequest) async throws -> User {
        let user = try signUpResult.get()
        storedUser = user
        return user
    }

    func signOut() async throws {
        signOutCallCount += 1
        storedUser = nil
    }

    func sendPasswordReset(toEmail email: String) async throws {}
    func deleteAccount() async throws { storedUser = nil }

    private final class ContinuationBox: @unchecked Sendable {
        var continuation: AsyncStream<User?>.Continuation?
    }
}

// MARK: - Remote sessions

final class MockPhotoSessionRepository: PhotoSessionRepositoryProtocol, @unchecked Sendable {

    var sessions: [PhotoSession] = []
    var fetchError: Error?
    var publishError: Error?
    var updateError: Error?

    /// Snapshots delivered by `sessionUpdates`, in order.
    var streamSnapshots: [[PhotoSession]] = []
    /// Thrown by `sessionUpdates` after the snapshots are drained.
    var streamError: Error?

    private(set) var publishedSessions: [PhotoSession] = []
    private(set) var fetchCallCount = 0
    private(set) var deletedIds: [String] = []

    // Reading

    func sessions(matching query: PhotoSessionQuery) async throws -> [PhotoSession] {
        fetchCallCount += 1
        if let fetchError { throw fetchError }
        return query.apply(to: sessions)
    }

    func session(id: String) async throws -> PhotoSession? {
        if let fetchError { throw fetchError }
        return sessions.first { $0.id == id }
    }

    // Writing

    @discardableResult
    func publish(_ session: PhotoSession) async throws -> PhotoSession {
        if let publishError { throw publishError }
        publishedSessions.append(session)
        sessions.append(session)
        return session
    }

    @discardableResult
    func update(_ session: PhotoSession) async throws -> PhotoSession {
        if let updateError { throw updateError }
        sessions.removeAll { $0.id == session.id }
        sessions.append(session)
        return session
    }

    func updateStatus(_ status: SessionStatus, forSessionId id: String) async throws {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index] = sessions[index].copy(status: status)
    }

    func delete(sessionId id: String) async throws {
        deletedIds.append(id)
        sessions.removeAll { $0.id == id }
    }

    // Observing

    func sessionUpdates(
        matching query: PhotoSessionQuery
    ) -> AsyncThrowingStream<[PhotoSession], Error> {
        let snapshots = streamSnapshots
        let error = streamError

        return AsyncThrowingStream { continuation in
            for snapshot in snapshots {
                continuation.yield(query.apply(to: snapshot))
            }
            continuation.finish(throwing: error)
        }
    }
}

// MARK: - Local cache

/// In-memory `LocalPhotoSessionRepositoryProtocol`. Mirrors the SwiftData
/// semantics that matter to callers: upsert-by-id and query filtering.
final class MockLocalPhotoSessionRepository: LocalPhotoSessionRepositoryProtocol, @unchecked Sendable {

    var storage: [String: PhotoSession] = [:]
    var syncStamp: Date?

    var readError: Error?
    var writeError: Error?

    private(set) var upsertCallCount = 0
    private(set) var deletedIds: [String] = []
    private(set) var clearCallCount = 0
    private(set) var purgedStatuses: [(status: SessionStatus, cutoff: Date)] = []

    init(seed: [PhotoSession] = [], syncStamp: Date? = nil) {
        for session in seed { storage[session.id] = session }
        self.syncStamp = syncStamp
    }

    func sessions(matching query: PhotoSessionQuery) async throws -> [PhotoSession] {
        if let readError { throw readError }
        return query.apply(to: Array(storage.values))
    }

    func session(id: String) async throws -> PhotoSession? {
        if let readError { throw readError }
        return storage[id]
    }

    func upsert(_ sessions: [PhotoSession], syncedAt: Date) async throws {
        if let writeError { throw writeError }
        upsertCallCount += 1
        for session in sessions { storage[session.id] = session }
        syncStamp = syncedAt
    }

    func delete(sessionIds ids: [String]) async throws {
        if let writeError { throw writeError }
        deletedIds.append(contentsOf: ids)
        for id in ids { storage.removeValue(forKey: id) }
    }

    func clear() async throws {
        if let writeError { throw writeError }
        clearCallCount += 1
        storage.removeAll()
    }

    func lastSyncedAt() async throws -> Date? {
        if let readError { throw readError }
        return syncStamp
    }

    func purgeSessions(endedBefore date: Date) async throws {
        storage = storage.filter { $0.value.endTime >= date }
    }

    func purgeSessions(withStatus status: SessionStatus, endedBefore date: Date) async throws {
        purgedStatuses.append((status, date))
        storage = storage.filter { !($0.value.status == status && $0.value.endTime < date) }
    }
}

// MARK: - Sync service

final class MockSyncService: PhotoSessionSyncServiceProtocol, @unchecked Sendable {

    var snapshots: [PhotoSessionSnapshot] = []
    var streamError: Error?
    var refreshResult: Result<[PhotoSession], Error> = .success([])

    private(set) var refreshCallCount = 0
    private(set) var invalidateCallCount = 0
    private(set) var publishedSessions: [PhotoSession] = []

    func sessions(
        matching query: PhotoSessionQuery
    ) -> AsyncThrowingStream<PhotoSessionSnapshot, Error> {
        let snapshots = self.snapshots
        let error = streamError

        return AsyncThrowingStream { continuation in
            for snapshot in snapshots { continuation.yield(snapshot) }
            continuation.finish(throwing: error)
        }
    }

    @discardableResult
    func refresh(matching query: PhotoSessionQuery) async throws -> [PhotoSession] {
        refreshCallCount += 1
        return try refreshResult.get()
    }

    @discardableResult
    func publish(_ session: PhotoSession) async throws -> PhotoSession {
        publishedSessions.append(session)
        return session
    }

    func invalidateCache() async throws { invalidateCallCount += 1 }
}

// MARK: - Location

final class MockLocationManager: LocationManagerProtocol, @unchecked Sendable {

    var authorization: LocationAuthorization = .whenInUse
    var location: Coordinate = try! Coordinate(latitude: 14.5995, longitude: 120.9842)
    var locationError: Error?

    private(set) var requestAuthorizationCallCount = 0
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0

    func authorizationStatus() async -> LocationAuthorization { authorization }

    @discardableResult
    func requestWhenInUseAuthorization() async -> LocationAuthorization {
        requestAuthorizationCallCount += 1
        return authorization
    }

    func currentLocation() async throws -> Coordinate {
        if let locationError { throw locationError }
        return location
    }

    func startUpdatingLocation() async { startCallCount += 1 }
    func stopUpdatingLocation() async { stopCallCount += 1 }

    func locationUpdates() -> AsyncThrowingStream<Coordinate, Error> {
        let coordinate = location
        return AsyncThrowingStream { continuation in
            continuation.yield(coordinate)
            continuation.finish()
        }
    }
}

// MARK: - Navigation spies
//
// Record navigation *events* rather than rendering views, which is what makes
// "did the ViewModel navigate?" assertable without a UI.

@MainActor
final class SpyAuthNavigator: AuthNavigating {
    private(set) var showSignUpCount = 0
    private(set) var showLoginCount = 0
    private(set) var showForgotPasswordCount = 0
    private(set) var authenticatedUsers: [User] = []

    func showSignUp() { showSignUpCount += 1 }
    func showLogin() { showLoginCount += 1 }
    func showForgotPassword() { showForgotPasswordCount += 1 }
    func authenticationDidSucceed(with user: User) { authenticatedUsers.append(user) }
}

@MainActor
final class SpyMainCoordinator: MainCoordinatorProtocol {
    var canPublishSessions = true

    private(set) var detailSessionIds: [String] = []
    private(set) var createSessionCount = 0
    private(set) var editedSessions: [PhotoSession] = []
    private(set) var mySessionsCount = 0
    private(set) var finishedSessions: [PhotoSession?] = []
    private(set) var cancelCount = 0
    private(set) var goBackCount = 0
    private(set) var returnToMapCount = 0
    private(set) var signOutCount = 0

    func showSessionDetail(sessionId: String) { detailSessionIds.append(sessionId) }
    func showSessionDetail(for session: PhotoSession) { detailSessionIds.append(session.id) }
    func goBack() { goBackCount += 1 }
    func returnToMap() { returnToMapCount += 1 }
    func showCreateSession() { createSessionCount += 1 }
    func showEditSession(_ session: PhotoSession) { editedSessions.append(session) }
    func showMySessions() { mySessionsCount += 1 }
    func sessionEditingDidFinish(with session: PhotoSession?) { finishedSessions.append(session) }
    func cancelSessionEditing() { cancelCount += 1 }
    func requestSignOut() { signOutCount += 1 }
}
