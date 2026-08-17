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

    // MARK: Read

    func sessions(matching query: PhotoSessionQuery) async throws -> [PhotoSession] {
        let descriptor = FetchDescriptor<PhotoSessionEntity>(
            predicate: Self.predicate(for: query)
        )
        let entities = try modelContext.fetch(descriptor)
        // Region, sort and limit are finished in memory by the shared helper so
        // the cache and Firestore interpret a query identically.
        return query.apply(to: entities.map(\.domainValue))
    }

    func session(id: String) async throws -> PhotoSession? {
        try entity(id: id)?.domainValue
    }

    // MARK: Write

    func upsert(_ sessions: [PhotoSession], syncedAt: Date) async throws {
        for session in sessions {
            if let existing = try entity(id: session.id) {
                existing.apply(session, syncedAt: syncedAt)
            } else {
                modelContext.insert(PhotoSessionEntity(session, syncedAt: syncedAt))
            }
        }
        try modelContext.save()
    }

    func delete(sessionIds ids: [String]) async throws {
        guard !ids.isEmpty else { return }
        let idSet = Set(ids)
        try modelContext.delete(
            model: PhotoSessionEntity.self,
            where: #Predicate { idSet.contains($0.id) }
        )
        try modelContext.save()
    }

    func clear() async throws {
        try modelContext.delete(model: PhotoSessionEntity.self)
        try modelContext.save()
    }

    // MARK: Cache maintenance

    func lastSyncedAt() async throws -> Date? {
        var descriptor = FetchDescriptor<PhotoSessionEntity>(
            sortBy: [SortDescriptor(\.lastSyncedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.lastSyncedAt
    }

    func purgeSessions(endedBefore date: Date) async throws {
        try modelContext.delete(
            model: PhotoSessionEntity.self,
            where: #Predicate { $0.endTime < date }
        )
        try modelContext.save()
    }

    // MARK: Helpers

    private func entity(id: String) throws -> PhotoSessionEntity? {
        var descriptor = FetchDescriptor<PhotoSessionEntity>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
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
