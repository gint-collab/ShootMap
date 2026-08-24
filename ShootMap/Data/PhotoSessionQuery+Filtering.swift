//
//  PhotoSessionQuery+Filtering.swift
//  ShootMap
//
//  Created by Septuagint Murito on 8/17/26.
//

import Foundation

/// In-memory application of a `PhotoSessionQuery`.
///
/// Both the Firestore and SwiftData repositories push what they can down into
/// their store, then finish here. Sharing one implementation guarantees the
/// cache and the server agree on what a query *means* — otherwise a cached
/// snapshot and a remote snapshot could legitimately disagree.
nonisolated extension PhotoSessionQuery {

    func apply(to sessions: [PhotoSession]) -> [PhotoSession] {
        var result = sessions.filter(matches)
        result = Self.sorted(result, by: sort)
        if let limit, result.count > limit {
            result = Array(result.prefix(limit))
        }
        return result
    }

    func matches(_ session: PhotoSession) -> Bool {
        if let photographerId, session.photographerId != photographerId { return false }
        if !statuses.isEmpty, !statuses.contains(session.status) { return false }
        if let dateRange, !dateRange.contains(session.startTime) { return false }
        if let region, !region.contains(session.coordinate) { return false }
        return true
    }

    private static func sorted(
        _ sessions: [PhotoSession],
        by sort: PhotoSessionSort
    ) -> [PhotoSession] {
        switch sort {
        case .startTimeAscending:
            sessions.sorted { $0.startTime < $1.startTime }
        case .startTimeDescending:
            sessions.sorted { $0.startTime > $1.startTime }
        case .createdAtDescending:
            sessions.sorted { $0.createdAt > $1.createdAt }
        }
    }
}
