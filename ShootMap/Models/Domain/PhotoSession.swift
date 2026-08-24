//
//  PhotoSession.swift
//  ShootMap
//
//  Created by Septuagint Murito on 8/15/26.
//

import Foundation

/// A photographer's scheduled shoot pinned to a location and time range.
/// Pure value type — no Firebase, no SwiftData, no UI.
nonisolated struct PhotoSession: DomainEntity, GeoLocatable, TimeBounded, SocialPagePresentable {
    static let minimumDuration: TimeInterval = 60 * 5        // 5 minutes
    static let maximumDuration: TimeInterval = 60 * 60 * 24  // 24 hours

    let id: String
    let photographerId: String
    let photographerName: String
    let facebookPageName: String?
    let facebookPageURL: URL?
    let latitude: Double
    let longitude: Double
    let date: Date
    let startTime: Date
    let endTime: Date
    let createdAt: Date
    let status: SessionStatus

    init(
        id: String,
        photographerId: String,
        photographerName: String,
        facebookPageName: String? = nil,
        facebookPageURL: URL? = nil,
        latitude: Double,
        longitude: Double,
        date: Date,
        startTime: Date,
        endTime: Date,
        createdAt: Date = .now,
        status: SessionStatus = .scheduled
    ) {
        self.id = id
        self.photographerId = photographerId
        self.photographerName = photographerName.trimmed
        self.facebookPageName = facebookPageName?.trimmedNonEmpty
        self.facebookPageURL = facebookPageURL
        self.latitude = latitude
        self.longitude = longitude
        self.date = date
        self.startTime = startTime
        self.endTime = endTime
        self.createdAt = createdAt
        self.status = status
    }

    /// Convenience init taking an already-validated `Coordinate`.
    init(
        id: String,
        photographerId: String,
        photographerName: String,
        facebookPageName: String? = nil,
        facebookPageURL: URL? = nil,
        coordinate: Coordinate,
        date: Date,
        startTime: Date,
        endTime: Date,
        createdAt: Date = .now,
        status: SessionStatus = .scheduled
    ) {
        self.init(
            id: id,
            photographerId: photographerId,
            photographerName: photographerName,
            facebookPageName: facebookPageName,
            facebookPageURL: facebookPageURL,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            date: date,
            startTime: startTime,
            endTime: endTime,
            createdAt: createdAt,
            status: status
        )
    }
}

// MARK: - GeoLocatable

nonisolated extension PhotoSession {
    /// Falls back to `Coordinate.zero` only if the stored raw values are out of range
    /// (legacy/corrupt records). `validate()` is the guard against that ever persisting.
    var coordinate: Coordinate {
        (try? Coordinate(latitude: latitude, longitude: longitude)) ?? .zero
    }
}

// MARK: - Validation

nonisolated extension PhotoSession: Validatable {
    func validate(calendar: Calendar = .current) throws {
        guard !id.trimmed.isEmpty, !photographerId.trimmed.isEmpty else {
            throw DomainValidationError.emptyIdentifier
        }
        guard !photographerName.isEmpty else {
            throw DomainValidationError.emptyDisplayName
        }

        _ = try Coordinate(latitude: latitude, longitude: longitude)

        guard endTime > startTime else {
            throw DomainValidationError.endTimeNotAfterStartTime(start: startTime, end: endTime)
        }
        guard duration >= Self.minimumDuration else {
            throw DomainValidationError.sessionDurationTooShort(minimum: Self.minimumDuration)
        }
        guard duration <= Self.maximumDuration else {
            throw DomainValidationError.sessionDurationTooLong(maximum: Self.maximumDuration)
        }
        guard calendar.isDate(startTime, inSameDayAs: date) else {
            throw DomainValidationError.sessionTimesNotOnSessionDate
        }
    }

    func validate() throws {
        try validate(calendar: .current)
    }
}

// MARK: - Behaviour

nonisolated extension PhotoSession {
    var isVisibleOnMap: Bool { status.isActive }

    func isUpcoming(now: Date = .now) -> Bool {
        status == .scheduled && startTime > now
    }

    /// Returns a copy with a new status, or `nil` if the transition is illegal.
    func transitioned(to next: SessionStatus) -> PhotoSession? {
        guard status.canTransition(to: next) else { return nil }
        return copy(status: next)
    }

    func copy(status newStatus: SessionStatus) -> PhotoSession {
        PhotoSession(
            id: id,
            photographerId: photographerId,
            photographerName: photographerName,
            facebookPageName: facebookPageName,
            facebookPageURL: facebookPageURL,
            latitude: latitude,
            longitude: longitude,
            date: date,
            startTime: startTime,
            endTime: endTime,
            createdAt: createdAt,
            status: newStatus
        )
    }
}
