//
//  CoordinateRegion.swift
//  ShootMap
//
//  Created by Septuagint Murito on 8/15/26.
//

import Foundation

/// A rectangular map region expressed purely in domain terms.
/// Deliberately mirrors — but does not depend on — `MKCoordinateRegion`,
/// so repositories can take a viewport without importing MapKit.
nonisolated struct CoordinateRegion: Hashable, Sendable, Codable {
    let center: Coordinate
    let latitudeDelta: Double
    let longitudeDelta: Double

    init(center: Coordinate, latitudeDelta: Double, longitudeDelta: Double) {
        self.center = center
        self.latitudeDelta = abs(latitudeDelta)
        self.longitudeDelta = abs(longitudeDelta)
    }

    /// Inclusive bounds, clamped to legal coordinate space.
    var latitudeBounds: ClosedRange<Double> {
        let lower = max(Coordinate.latitudeRange.lowerBound, center.latitude - latitudeDelta / 2)
        let upper = min(Coordinate.latitudeRange.upperBound, center.latitude + latitudeDelta / 2)
        return lower...max(lower, upper)
    }

    var longitudeBounds: ClosedRange<Double> {
        let lower = max(Coordinate.longitudeRange.lowerBound, center.longitude - longitudeDelta / 2)
        let upper = min(Coordinate.longitudeRange.upperBound, center.longitude + longitudeDelta / 2)
        return lower...max(lower, upper)
    }

    func contains(_ coordinate: Coordinate) -> Bool {
        latitudeBounds.contains(coordinate.latitude)
            && longitudeBounds.contains(coordinate.longitude)
    }
}
