//
//  PhotoSessionEntity.swift
//  ShootMap
//
//  Created by Septuagint Murito on 8/15/26.
//

import Foundation
import SwiftData

/// Local cache record for a photography session.
///
/// This is a **persistence type only** — it holds no domain rules, no validation,
/// and no Firebase types. Mapping to/from `PhotoSession` lives in the data layer.
///
/// Scalar, indexed columns (`latitude` / `longitude` / `date` / `startTime` / `status`)
/// are stored flat so `#Predicate` can filter map regions and date ranges in the store
/// rather than in memory.
@Model
final class PhotoSessionEntity {

    /// Firestore document id. Unique so upserts collapse onto a single row.
    @Attribute(.unique) var id: String

    // MARK: Photographer

    var photographerId: String
    var photographerName: String
    var facebookPageName: String?
    /// Stored as `String` (not `URL`) to keep the column simple and query-friendly.
    var facebookPageURL: String?

    // MARK: Location — flat scalars for bounding-box map queries

    var latitude: Double
    var longitude: Double

    // MARK: Schedule — flat dates for range filtering

    /// Calendar day the session belongs to.
    var date: Date
    var startTime: Date
    var endTime: Date

    // MARK: Metadata

    var createdAt: Date

    /// Raw value of `SessionStatus`. Stored as `String` so it is directly usable
    /// inside `#Predicate` and stays forward-compatible with unknown values.
    var status: String

    /// When this row was last reconciled with the remote source of truth.
    var lastSyncedAt: Date

    // MARK: Indexes
    //
    // Must live inside the class body — `#Index` expands into schema metadata
    // on the `@Model` type itself, so it is invalid in an extension.
    // Backs the hot access paths: map viewport lookups, upcoming-session lists,
    // and a photographer's own sessions. (`id` is already indexed via `.unique`.)
    #Index<PhotoSessionEntity>(
        [\.status],
        [\.startTime],
        [\.latitude, \.longitude],
        [\.status, \.startTime],
        [\.photographerId, \.startTime]
    )

    init(
        id: String,
        photographerId: String,
        photographerName: String,
        facebookPageName: String? = nil,
        facebookPageURL: String? = nil,
        latitude: Double,
        longitude: Double,
        date: Date,
        startTime: Date,
        endTime: Date,
        createdAt: Date,
        status: String,
        lastSyncedAt: Date
    ) {
        self.id = id
        self.photographerId = photographerId
        self.photographerName = photographerName
        self.facebookPageName = facebookPageName
        self.facebookPageURL = facebookPageURL
        self.latitude = latitude
        self.longitude = longitude
        self.date = date
        self.startTime = startTime
        self.endTime = endTime
        self.createdAt = createdAt
        self.status = status
        self.lastSyncedAt = lastSyncedAt
    }
}
