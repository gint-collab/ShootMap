//
//  SwiftDataPhotoSessionRepository.swift
//  ShootMap
//
//  Created by Septuagint Murito on 8/17/26.
//

import Foundation
import SwiftData

/// SwiftData-backed local cache.
///
/// A `@ModelActor` so every `ModelContext` touch is serialised off the main
/// actor. Neither `ModelContext` nor `PhotoSessionEntity` escapes: the actor
/// converts to `PhotoSession` before returning, which is also what keeps the
/// results `Sendable`.
@ModelActor
actor SwiftDataPhotoSessionRepository: LocalPhotoSessionRepositoryProtocol {

    // MARK: - Named API

    /// Inserts or updates a single session.
    func save(_ session: PhotoSession, syncedAt: Date = .now) async throws {
        try await upsert([session], syncedAt: syncedAt)
    }

    /// Inserts or updates a batch in one transaction.
    func saveMany(_ sessions: [PhotoSession], syncedAt: Date = .now) async throws {
        try await upsert(sessions, syncedAt: syncedAt)
    }

    /// Every cached session, soonest first.
    func fetchAll() async throws -> [PhotoSession] {
        try await sessions(matching: PhotoSessionQuery())
    }

    /// Sessions whose start time falls on the calendar day containing `date`.
    func fetchSessions(
        for date: Date,
        calendar: Calendar = .current
    ) async throws -> [PhotoSession] {
        guard let range = calendar.dayRange(containing: date) else { return [] }
        return try await sessions(matching: PhotoSessionQuery(dateRange: range))
    }

    func findByID(id: String) async throws -> PhotoSession? {
        try await session(id: id)
    }

    func delete(id: String) async throws {
        try await delete(sessionIds: [id])
    }

    func deleteAll() async throws {
        try await clear()
    }

    // MARK: - LocalPhotoSessionRepositoryProtocol

    func sessions(matching query: PhotoSessionQuery) async throws -> [PhotoSession] {
        let descriptor = FetchDescriptor<PhotoSessionEntity>(
            predicate: Self.predicate(for: query)
        )
        let entities = try perform("fetch sessions") {
            try modelContext.fetch(descriptor)
        }
        // Region, sort and limit are finished in memory by the shared helper so
        // the cache and Firestore interpret a query identically.
        return query.apply(to: entities.map(\.domainValue))
    }

    func session(id: String) async throws -> PhotoSession? {
        try perform("fetch session") { try entity(id: id)?.domainValue }
    }

    /// Idempotent: replaying the same batch reuses the unique `id` row rather
    /// than duplicating it, so a repeated sync is a no-op beyond `lastSyncedAt`.
    func upsert(_ sessions: [PhotoSession], syncedAt: Date) async throws {
        guard !sessions.isEmpty else { return }

        try perform("save sessions") {
            for session in sessions {
                if let existing = try entity(id: session.id) {
                    existing.apply(session, syncedAt: syncedAt)
                } else {
                    modelContext.insert(PhotoSessionEntity(session, syncedAt: syncedAt))
                }
            }
            try commit()
        }
    }

    func delete(sessionIds ids: [String]) async throws {
        guard !ids.isEmpty else { return }
        let idSet = Set(ids)

        try perform("delete sessions") {
            try modelContext.delete(
                model: PhotoSessionEntity.self,
                where: #Predicate { idSet.contains($0.id) }
            )
            try commit()
        }
    }

    func clear() async throws {
        try perform("clear cache") {
            try modelContext.delete(model: PhotoSessionEntity.self)
            try commit()
        }
    }

    // MARK: Cache maintenance

    func lastSyncedAt() async throws -> Date? {
        var descriptor = FetchDescriptor<PhotoSessionEntity>(
            sortBy: [SortDescriptor(\.lastSyncedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try perform("read sync stamp") {
            try modelContext.fetch(descriptor).first?.lastSyncedAt
        }
    }

    func purgeSessions(endedBefore date: Date) async throws {
        try perform("purge sessions") {
            try modelContext.delete(
                model: PhotoSessionEntity.self,
                where: #Predicate { $0.endTime < date }
            )
            try commit()
        }
    }

    // MARK: - Helpers

    private func entity(id: String) throws -> PhotoSessionEntity? {
        var descriptor = FetchDescriptor<PhotoSessionEntity>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    /// Rolls the context back on failure so a partially-applied batch cannot
    /// leave the cache in a state that never existed remotely.
    private func commit() throws {
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    /// Single translation point: any store error becomes `.cacheFailure`, so
    /// `SwiftDataError` never leaves this type.
    private func perform<T>(_ operation: String, _ work: () throws -> T) throws -> T {
        do {
            return try work()
        } catch let error as PhotoSessionError {
            throw error
        } catch {
            throw PhotoSessionError.cacheFailure(
                message: "Failed to \(operation): \(error.localizedDescription)"
            )
        }
    }

    /// Only the predicates SwiftData can express are pushed into the store.
    /// A `CoordinateRegion` is a bounding box on two columns, which `#Predicate`
    /// handles poorly, so it is left to the in-memory pass.
    private static func predicate(
        for query: PhotoSessionQuery
    ) -> Predicate<PhotoSessionEntity>? {
        let photographerId = query.photographerId
        let rawStatuses = Set(query.statuses.map(\.rawValue))
        let lowerBound = query.dateRange?.lowerBound
        let upperBound = query.dateRange?.upperBound

        return #Predicate<PhotoSessionEntity> { entity in
            (photographerId == nil || entity.photographerId == photographerId!)
                && (rawStatuses.isEmpty || rawStatuses.contains(entity.status))
                && (lowerBound == nil || entity.startTime >= lowerBound!)
                && (upperBound == nil || entity.startTime <= upperBound!)
        }
    }
}

// MARK: - Day bounds

private extension Calendar {
    /// Closed range covering the calendar day containing `date`. The upper bound
    /// is nudged back a millisecond so a session starting exactly at midnight
    /// belongs to one day only, never both.
    func dayRange(containing date: Date) -> ClosedRange<Date>? {
        let start = startOfDay(for: date)
        guard let next = self.date(byAdding: .day, value: 1, to: start) else { return nil }
        return start...next.addingTimeInterval(-0.001)
    }
}

// MARK: - Mapping

private extension PhotoSessionEntity {

    convenience init(_ session: PhotoSession, syncedAt: Date) {
        self.init(
            id: session.id,
            photographerId: session.photographerId,
            photographerName: session.photographerName,
            facebookPageName: session.facebookPageName,
            facebookPageURL: session.facebookPageURL?.absoluteString,
            latitude: session.latitude,
            longitude: session.longitude,
            date: session.date,
            startTime: session.startTime,
            endTime: session.endTime,
            createdAt: session.createdAt,
            status: session.status.rawValue,
            lastSyncedAt: syncedAt
        )
    }

    /// Mutates in place so the unique `id` row is reused rather than duplicated.
    func apply(_ session: PhotoSession, syncedAt: Date) {
        photographerId = session.photographerId
        photographerName = session.photographerName
        facebookPageName = session.facebookPageName
        facebookPageURL = session.facebookPageURL?.absoluteString
        latitude = session.latitude
        longitude = session.longitude
        date = session.date
        startTime = session.startTime
        endTime = session.endTime
        createdAt = session.createdAt
        status = session.status.rawValue
        lastSyncedAt = syncedAt
    }

    var domainValue: PhotoSession {
        PhotoSession(
            id: id,
            photographerId: photographerId,
            photographerName: photographerName,
            facebookPageName: facebookPageName,
            facebookPageURL: facebookPageURL.flatMap(URL.init(string:)),
            latitude: latitude,
            longitude: longitude,
            date: date,
            startTime: startTime,
            endTime: endTime,
            createdAt: createdAt,
            status: SessionStatus(storedValue: status)
        )
    }
}
