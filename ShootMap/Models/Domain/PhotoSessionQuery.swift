//
//  PhotoSessionQuery.swift
//  ShootMap
//
//  Created by Septuagint Murito on 8/15/26.
//

import Foundation

/// Describes *what* sessions a caller wants, without saying *how* to fetch them.
/// Keeps repository interfaces from growing a new method per filter combination.
nonisolated struct PhotoSessionQuery: Hashable, Sendable {
    /// Map viewport to restrict results to. `nil` means "anywhere".
    var region: CoordinateRegion?

    /// Time window the session must start within. `nil` means "any time".
    var dateRange: ClosedRange<Date>?

    /// Restrict to a single photographer. `nil` means "all photographers".
    var photographerId: String?

    /// Statuses to include. Empty means "no status filter".
    var statuses: Set<SessionStatus>

    /// Upper bound on results; `nil` means unbounded.
    var limit: Int?

    var sort: PhotoSessionSort

    init(
        region: CoordinateRegion? = nil,
        dateRange: ClosedRange<Date>? = nil,
        photographerId: String? = nil,
        statuses: Set<SessionStatus> = [],
        limit: Int? = nil,
        sort: PhotoSessionSort = .startTimeAscending
    ) {
        self.region = region
        self.dateRange = dateRange
        self.photographerId = photographerId
        self.statuses = statuses
        self.limit = limit
        self.sort = sort
    }
}

nonisolated enum PhotoSessionSort: Hashable, Sendable {
    case startTimeAscending
    case startTimeDescending
    case createdAtDescending
}

// MARK: - Common queries

nonisolated extension PhotoSessionQuery {
    /// Everything a viewer should see on the map.
    ///
    /// Intentionally has **no date bound**: viewers browse every scheduled and
    /// in-progress session, including ones whose date has already passed. Only
    /// status decides visibility.
    static func visibleOnMap(in region: CoordinateRegion) -> Self {
        PhotoSessionQuery(
            region: region,
            statuses: [.scheduled, .ongoing]
        )
    }

    /// A photographer's own sessions, newest first.
    static func authored(by photographerId: String) -> Self {
        PhotoSessionQuery(photographerId: photographerId, sort: .createdAtDescending)
    }
}
