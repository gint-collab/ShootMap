//
//  FirestoreMapping.swift
//  ShootMap
//
//  Created by Septuagint Murito on 8/17/26.
//

import Foundation
import FirebaseFirestore

/// Errors raised when a remote document cannot be turned into a domain value.
nonisolated enum RemoteMappingError: Error, Equatable, Sendable {
    case malformedDocument(id: String, field: String)
}

/// Field names are the wire contract with Firestore. Centralised so a rename
/// is a one-line change rather than a hunt through string literals.
nonisolated enum SessionField {
    static let photographerId = "photographerId"
    static let photographerName = "photographerName"
    static let facebookPageName = "facebookPageName"
    static let facebookPageURL = "facebookPageURL"
    static let latitude = "latitude"
    static let longitude = "longitude"
    static let date = "date"
    static let startTime = "startTime"
    static let endTime = "endTime"
    static let createdAt = "createdAt"
    static let status = "status"
}

nonisolated enum UserField {
    static let email = "email"
    static let displayName = "displayName"
    static let facebookPageName = "facebookPageName"
    static let facebookPageURL = "facebookPageURL"
    static let role = "role"
    static let createdAt = "createdAt"
}

// MARK: - PhotoSession

nonisolated extension PhotoSession {

    /// Firestore payload. `id` is intentionally omitted — it is the document key.
    var firestoreData: [String: Any] {
        var data: [String: Any] = [
            SessionField.photographerId: photographerId,
            SessionField.photographerName: photographerName,
            SessionField.latitude: latitude,
            SessionField.longitude: longitude,
            SessionField.date: Timestamp(date: date),
            SessionField.startTime: Timestamp(date: startTime),
            SessionField.endTime: Timestamp(date: endTime),
            SessionField.createdAt: Timestamp(date: createdAt),
            SessionField.status: status.rawValue
        ]
        if let facebookPageName { data[SessionField.facebookPageName] = facebookPageName }
        if let facebookPageURL { data[SessionField.facebookPageURL] = facebookPageURL.absoluteString }
        return data
    }

    init(snapshot: DocumentSnapshot) throws {
        guard let data = snapshot.data() else {
            throw RemoteMappingError.malformedDocument(id: snapshot.documentID, field: "<root>")
        }
        try self.init(id: snapshot.documentID, data: data)
    }

    init(id: String, data: [String: Any]) throws {
        func required<T>(_ field: String, as type: T.Type = T.self) throws -> T {
            guard let value = data[field] as? T else {
                throw RemoteMappingError.malformedDocument(id: id, field: field)
            }
            return value
        }
        func requiredDate(_ field: String) throws -> Date {
            try required(field, as: Timestamp.self).dateValue()
        }

        self.init(
            id: id,
            photographerId: try required(SessionField.photographerId),
            photographerName: try required(SessionField.photographerName),
            facebookPageName: data[SessionField.facebookPageName] as? String,
            facebookPageURL: (data[SessionField.facebookPageURL] as? String).flatMap(URL.init(string:)),
            latitude: try required(SessionField.latitude),
            longitude: try required(SessionField.longitude),
            date: try requiredDate(SessionField.date),
            startTime: try requiredDate(SessionField.startTime),
            endTime: try requiredDate(SessionField.endTime),
            createdAt: try requiredDate(SessionField.createdAt),
            // Unknown values degrade rather than fail the whole document.
            status: SessionStatus(storedValue: data[SessionField.status] as? String)
        )
    }
}

// MARK: - User

nonisolated extension User {

    var firestoreData: [String: Any] {
        var data: [String: Any] = [
            UserField.email: email,
            UserField.displayName: displayName,
            UserField.role: role.rawValue,
            UserField.createdAt: Timestamp(date: createdAt)
        ]
        if let facebookPageName { data[UserField.facebookPageName] = facebookPageName }
        if let facebookPageURL { data[UserField.facebookPageURL] = facebookPageURL.absoluteString }
        return data
    }

    init(id: String, data: [String: Any]) {
        self.init(
            id: id,
            email: data[UserField.email] as? String ?? "",
            displayName: data[UserField.displayName] as? String ?? "",
            facebookPageName: data[UserField.facebookPageName] as? String,
            facebookPageURL: (data[UserField.facebookPageURL] as? String).flatMap(URL.init(string:)),
            role: UserRole(storedValue: data[UserField.role] as? String),
            createdAt: (data[UserField.createdAt] as? Timestamp)?.dateValue() ?? .now
        )
    }
}
