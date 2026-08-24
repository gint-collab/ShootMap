//
//  Coordinate.swift
//  ShootMap
//
//  Created by Septuagint Murito on 8/15/26.
//

import Foundation

/// A framework-agnostic geographic coordinate.
/// Deliberately does not import CoreLocation so the domain layer stays dependency-free.
nonisolated struct Coordinate: Hashable, Sendable, Codable {
    static let latitudeRange: ClosedRange<Double> = -90...90
    static let longitudeRange: ClosedRange<Double> = -180...180

    let latitude: Double
    let longitude: Double

    /// Safe fallback used when raw persisted values cannot form a valid coordinate.
    static let zero: Coordinate = Coordinate(unchecked: 0, longitude: 0)

    private init(unchecked latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Failable init that enforces the coordinate invariants at construction time.
    init(latitude: Double, longitude: Double) throws {
        guard latitude.isFinite, Self.latitudeRange.contains(latitude) else {
            throw DomainValidationError.invalidLatitude(latitude)
        }
        guard longitude.isFinite, Self.longitudeRange.contains(longitude) else {
            throw DomainValidationError.invalidLongitude(longitude)
        }
        self.latitude = latitude
        self.longitude = longitude
    }
}

nonisolated extension Coordinate: Validatable {
    func validate() throws {
        _ = try Coordinate(latitude: latitude, longitude: longitude)
    }
}
