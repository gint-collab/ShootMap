//
//  DataLayerTests.swift
//  ShootMapTests
//

import Testing
import Foundation
import SwiftData
@testable import ShootMap

// MARK: - Sync service

@Suite("PhotoSessionSyncService")
struct PhotoSessionSyncServiceTests {

    private func makeSUT(
        cached: [PhotoSession] = [],
        policy: CacheRetentionPolicy = .default
    ) -> (PhotoSessionSyncService, MockPhotoSessionRepository, MockLocalPhotoSessionRepository) {
        let remote = MockPhotoSessionRepository()
        let local = MockLocalPhotoSessionRepository(seed: cached)
        let sut = PhotoSessionSyncService(remote: remote, local: local, retentionPolicy: policy)
        return (sut, remote, local)
    }

    @Test("Refresh writes remote results through to the cache")
    func refreshPopulatesCache() async throws {
        let session = Fixture.session(id: "s1")
        let (sut, remote, local) = makeSUT()
        remote.sessions = [session]

        let result = try await sut.refresh(matching: PhotoSessionQuery())

        #expect(result.map(\.id) == ["s1"])
        #expect(local.storage["s1"] != nil)
    }

    @Test("Reconciliation removes cached sessions that vanished remotely")
    func removesDeletedSessions() async throws {
        let kept = Fixture.session(id: "kept")
        let deleted = Fixture.session(id: "deleted")
        let (sut, remote, local) = makeSUT(cached: [kept, deleted])

        remote.sessions = [kept]   // "deleted" is gone from the server

        try await sut.refresh(matching: PhotoSessionQuery())

        #expect(local.storage["kept"] != nil)
        #expect(local.storage["deleted"] == nil)
    }

    @Test("An unchanged batch performs no cache writes")
    func idempotentSync() async throws {
        let session = Fixture.session(id: "s1")
        let (sut, remote, local) = makeSUT(cached: [session])
        remote.sessions = [session]

        let report = try await sut.synchronize(matching: PhotoSessionQuery())

        #expect(report.inserted == 0)
        #expect(report.updated == 0)
        #expect(report.removed == 0)
        #expect(local.upsertCallCount == 0)
    }

    @Test("A changed session is counted as an update")
    func detectsUpdates() async throws {
        let original = Fixture.session(id: "s1", status: .scheduled)
        let changed = original.copy(status: .ongoing)
        let (sut, remote, _) = makeSUT(cached: [original])
        remote.sessions = [changed]

        let report = try await sut.synchronize(matching: PhotoSessionQuery())

        #expect(report.updated == 1)
        #expect(report.inserted == 0)
    }

    @Test("Firestore failure leaves the cache completely intact")
    func remoteFailurePreservesCache() async {
        let cached = Fixture.session(id: "cached")
        let (sut, remote, local) = makeSUT(cached: [cached])
        remote.fetchError = TestError.network

        await #expect(throws: TestError.network) {
            try await sut.refresh(matching: PhotoSessionQuery())
        }

        // Nothing was deleted or overwritten by the failed pass.
        #expect(local.storage["cached"] != nil)
        #expect(local.deletedIds.isEmpty)
        #expect(local.upsertCallCount == 0)
    }

    @Test("A cache write failure does not swallow the published session")
    func cacheFailureDuringPublish() async throws {
        let (sut, _, local) = makeSUT()
        local.writeError = TestError.cache

        let session = Fixture.session()
        let stored = try await sut.publish(session)

        // The remote write succeeded, so the caller still gets its result.
        #expect(stored.id == session.id)
    }

    @Test("Publish failure never leaves a local trace")
    func publishFailure() async {
        let (sut, remote, local) = makeSUT()
        remote.publishError = TestError.network

        await #expect(throws: TestError.network) {
            try await sut.publish(Fixture.session())
        }

        #expect(local.storage.isEmpty)
    }

    @Test("The stream yields cache first, then remote")
    func streamOrdering() async throws {
        let cached = Fixture.session(id: "cached")
        let remoteSession = Fixture.session(id: "remote")
        let (sut, remote, _) = makeSUT(cached: [cached])
        remote.streamSnapshots = [[cached, remoteSession]]

        var origins: [DataOrigin] = []
        for try await snapshot in sut.sessions(matching: PhotoSessionQuery()) {
            origins.append(snapshot.origin)
        }

        #expect(origins.first == .cache)
        #expect(origins.contains(.remote))
    }

    @Test("Cancelling a session updates it rather than deleting it")
    func cancelKeepsRecord() async throws {
        let session = Fixture.session(id: "s1", status: .scheduled)
        let (sut, remote, local) = makeSUT(cached: [session])
        remote.sessions = [session]

        try await sut.cancel(sessionId: "s1")

        #expect(local.storage["s1"]?.status == .cancelled)
    }

    @Test("Invalidating the cache clears it")
    func invalidate() async throws {
        let (sut, _, local) = makeSUT(cached: [Fixture.session()])

        try await sut.invalidateCache()

        #expect(local.clearCallCount == 1)
        #expect(local.storage.isEmpty)
    }

    // MARK: Retention

    @Test("Cleanup keeps future sessions and evicts aged-out ones")
    func retentionPolicy() async throws {
        let now = Fixture.now

        let future = Fixture.session(id: "future", start: now.addingTimeInterval(.days(2)))
        let today = Fixture.session(id: "today", start: now.addingTimeInterval(3_600))
        let oldCompleted = Fixture.session(
            id: "old-completed",
            start: now.addingTimeInterval(-.days(40)),
            status: .completed
        )
        let recentCompleted = Fixture.session(
            id: "recent-completed",
            start: now.addingTimeInterval(-.days(3)),
            status: .completed
        )
        let oldCancelled = Fixture.session(
            id: "old-cancelled",
            start: now.addingTimeInterval(-.days(10)),
            status: .cancelled
        )

        let (sut, _, local) = makeSUT(
            cached: [future, today, oldCompleted, recentCompleted, oldCancelled]
        )

        try await sut.cleanUpCache(now: now)

        #expect(local.storage["future"] != nil)             // never evicted
        #expect(local.storage["today"] != nil)              // today is kept
        #expect(local.storage["recent-completed"] != nil)   // inside 30 days
        #expect(local.storage["old-completed"] == nil)      // beyond 30 days
        #expect(local.storage["old-cancelled"] == nil)      // beyond 7 days
    }

    @Test("Retention periods are configurable")
    func configurableRetention() {
        let policy = CacheRetentionPolicy(
            completedRetention: .days(1),
            cancelledRetention: .days(1)
        )
        let session = Fixture.session(
            start: Fixture.now.addingTimeInterval(-.days(2)),
            status: .completed
        )

        #expect(policy.isExpired(session, now: Fixture.now))
        #expect(!CacheRetentionPolicy.unlimited.isExpired(session, now: Fixture.now))
    }

    @Test("A future scheduled session is never expired by any policy")
    func futureNeverExpires() {
        let future = Fixture.session(start: Fixture.now.addingTimeInterval(.days(5)))
        let aggressive = CacheRetentionPolicy(
            completedRetention: 0,
            cancelledRetention: 0,
            stalePeriod: 0
        )

        #expect(!aggressive.isExpired(future, now: Fixture.now))
    }
}

// MARK: - SwiftData repository

@Suite("SwiftDataPhotoSessionRepository")
struct SwiftDataPhotoSessionRepositoryTests {

    /// A fresh in-memory store per test — no disk, no shared state.
    private func makeSUT() throws -> SwiftDataPhotoSessionRepository {
        let container = try AppDependencyContainer.makeModelContainer(inMemory: true)
        return SwiftDataPhotoSessionRepository(modelContainer: container)
    }

    @Test("A saved session can be read back")
    func saveAndFetch() async throws {
        let sut = try makeSUT()
        let session = Fixture.session(id: "s1")

        try await sut.save(session)
        let found = try await sut.findByID(id: "s1")

        #expect(found?.id == "s1")
        #expect(found?.photographerName == session.photographerName)
        #expect(found?.facebookPageURL == session.facebookPageURL)
        #expect(found?.status == .scheduled)
    }

    @Test("Upserting the same id updates rather than duplicating")
    func upsertIsIdempotent() async throws {
        let sut = try makeSUT()
        let session = Fixture.session(id: "s1", status: .scheduled)

        try await sut.save(session)
        try await sut.save(session.copy(status: .ongoing))

        let all = try await sut.fetchAll()
        #expect(all.count == 1)
        #expect(all.first?.status == .ongoing)
    }

    @Test("saveMany stores a whole batch")
    func saveMany() async throws {
        let sut = try makeSUT()
        let sessions = (1...3).map { Fixture.session(id: "s\($0)") }

        try await sut.saveMany(sessions)

        #expect(try await sut.fetchAll().count == 3)
    }

    @Test("Sessions can be fetched by calendar day")
    func fetchByDate() async throws {
        let sut = try makeSUT()
        let today = Fixture.session(id: "today", start: Fixture.now.addingTimeInterval(3_600))
        let nextWeek = Fixture.session(id: "next-week", start: Fixture.now.addingTimeInterval(.days(7)))

        try await sut.saveMany([today, nextWeek])

        let result = try await sut.fetchSessions(for: Fixture.now, calendar: Fixture.calendar)
        #expect(result.map(\.id) == ["today"])
    }

    @Test("Deleting by id removes only that row")
    func deleteById() async throws {
        let sut = try makeSUT()
        try await sut.saveMany([Fixture.session(id: "a"), Fixture.session(id: "b")])

        try await sut.delete(id: "a")

        let remaining = try await sut.fetchAll().map(\.id)
        #expect(remaining == ["b"])
    }

    @Test("deleteAll empties the cache")
    func deleteAll() async throws {
        let sut = try makeSUT()
        try await sut.saveMany([Fixture.session(id: "a"), Fixture.session(id: "b")])

        try await sut.deleteAll()

        #expect(try await sut.fetchAll().isEmpty)
    }

    @Test("Queries filter by status and photographer")
    func queryFiltering() async throws {
        let sut = try makeSUT()
        let mine = Fixture.session(id: "mine", photographerId: "me", status: .scheduled)
        let theirs = Fixture.session(id: "theirs", photographerId: "them", status: .scheduled)
        let cancelled = Fixture.session(id: "cancelled", photographerId: "me", status: .cancelled)

        try await sut.saveMany([mine, theirs, cancelled])

        let byAuthor = try await sut.sessions(matching: .authored(by: "me"))
        #expect(Set(byAuthor.map(\.id)) == ["mine", "cancelled"])

        let active = try await sut.sessions(
            matching: PhotoSessionQuery(photographerId: "me", statuses: [.scheduled])
        )
        #expect(active.map(\.id) == ["mine"])
    }

    @Test("lastSyncedAt reports the most recent stamp")
    func syncStamp() async throws {
        let sut = try makeSUT()
        #expect(try await sut.lastSyncedAt() == nil)

        let stamp = Fixture.now
        try await sut.save(Fixture.session(), syncedAt: stamp)

        let recorded = try await sut.lastSyncedAt()
        #expect(recorded?.timeIntervalSince1970 == stamp.timeIntervalSince1970)
    }

    @Test("Status-aware purging evicts only the matching status")
    func statusAwarePurge() async throws {
        let sut = try makeSUT()
        let now = Fixture.now

        let oldCompleted = Fixture.session(
            id: "old-completed",
            start: now.addingTimeInterval(-.days(40)),
            status: .completed
        )
        let oldScheduled = Fixture.session(
            id: "old-scheduled",
            start: now.addingTimeInterval(-.days(40)),
            status: .scheduled
        )
        try await sut.saveMany([oldCompleted, oldScheduled])

        try await sut.purgeSessions(
            withStatus: .completed,
            endedBefore: now.addingTimeInterval(-.days(30))
        )

        let remaining = try await sut.fetchAll().map(\.id)
        #expect(remaining == ["old-scheduled"])
    }

    @Test("The retention policy applies across statuses in one pass")
    func retentionAcrossStatuses() async throws {
        let sut = try makeSUT()
        let now = Fixture.now

        try await sut.saveMany([
            Fixture.session(id: "future", start: now.addingTimeInterval(.days(3))),
            Fixture.session(id: "old-completed", start: now.addingTimeInterval(-.days(40)), status: .completed),
            Fixture.session(id: "old-cancelled", start: now.addingTimeInterval(-.days(10)), status: .cancelled)
        ])

        try await sut.applyRetentionPolicy(.default, now: now)

        #expect(try await sut.fetchAll().map(\.id) == ["future"])
    }

    @Test("Reading a missing session returns nil rather than throwing")
    func missingSession() async throws {
        let sut = try makeSUT()
        #expect(try await sut.findByID(id: "nope") == nil)
    }
}
