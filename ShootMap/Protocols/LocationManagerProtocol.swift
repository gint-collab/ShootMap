//
//  LocationManagerProtocol.swift
//  ShootMap
//
//  Created by Septuagint Murito on 8/17/26.
//

import Foundation

/// Domain-level mirror of `CLAuthorizationStatus`, so callers never import CoreLocation.
nonisolated enum LocationAuthorization: Hashable, Sendable {
    case notDetermined
    case denied
    case restricted
    case whenInUse
    case always

    /// Whether the app may currently read the device location.
    var isAuthorized: Bool { self == .whenInUse || self == .always }

    /// The user has made a final choice the app cannot change by prompting.
    var isDenied: Bool { self == .denied || self == .restricted }
}

/// Failures surfaced by the location layer, free of CoreLocation types.
nonisolated enum LocationError: Error, Equatable, Sendable {
    case authorizationDenied
    case locationUnavailable
    case timedOut
}

extension LocationError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            "ShootMap needs location access to show sessions near you."
        case .locationUnavailable:
            "Couldn't determine your location."
        case .timedOut:
            "Locating you took too long. Please try again."
        }
    }
}

/// Supplies the device location as domain `Coordinate` values.
///
/// CoreLocation is the implementation detail — no `CLLocationManager`,
/// `CLLocation`, or `CLAuthorizationStatus` crosses this boundary, so map
/// ViewModels can be tested with a stub that replays fixed coordinates.
///
/// Every requirement is either `async` or a plain synchronous command, and none
/// use associated types, so a mock needs no framework and no ceremony.
nonisolated protocol LocationManagerProtocol: Sendable {

    // MARK: Authorization

    /// Current authorization, without prompting.
    func authorizationStatus() async -> LocationAuthorization

    /// Prompts for "when in use" access if undetermined, then reports the
    /// outcome. Returns the existing status immediately when the user has
    /// already decided, since no prompt can appear in that case.
    @discardableResult
    func requestWhenInUseAuthorization() async -> LocationAuthorization

    // MARK: Current location

    /// One-shot fix, used to centre the map on launch.
    func currentLocation() async throws -> Coordinate

    // MARK: Continuous updates

    /// Begins continuous updates, delivered through `locationUpdates()`.
    /// Idempotent — repeated calls do not stack.
    ///
    /// `async` because the implementation owns `CLLocationManager`, which is
    /// main-actor bound; awaiting is what lets a caller on any actor drive it.
    func startUpdatingLocation() async

    /// Ends the updates started by `startUpdatingLocation()`.
    /// Idempotent, and safe to call when updates were never started.
    func stopUpdatingLocation() async

    /// The stream of coordinates produced while updates are running.
    ///
    /// Separate from `startUpdatingLocation()` so several observers can share
    /// one hardware session, and so the caller controls the hardware lifetime
    /// explicitly rather than implicitly through subscription.
    func locationUpdates() -> AsyncThrowingStream<Coordinate, Error>
}
