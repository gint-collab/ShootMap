//
//  LocationManager.swift
//  ShootMap
//
//  Created by Septuagint Murito on 8/17/26.
//

import Foundation
import CoreLocation

/// CoreLocation-backed `LocationManagerProtocol`.
///
/// The only type in the app that imports CoreLocation. `CLLocationManager` must
/// live on a thread with an active run loop, so the whole class is `@MainActor`
/// and the delegate callbacks are bridged into continuations.
@MainActor
final class LocationManager: NSObject, LocationManagerProtocol {

    private let manager: CLLocationManager

    /// Pending one-shot `currentLocation()` callers.
    private var fixContinuations: [CheckedContinuation<Coordinate, Error>] = []
    /// Pending `requestWhenInUseAuthorization()` callers.
    private var authorizationContinuations: [CheckedContinuation<LocationAuthorization, Never>] = []
    /// Live subscribers of `locationUpdates()`.
    private var streamContinuations: [UUID: AsyncThrowingStream<Coordinate, Error>.Continuation] = [:]

    /// Whether `startUpdatingLocation()` has been called without a matching stop.
    /// Tracked explicitly so the hardware lifetime is driven by the caller, not
    /// by whether anyone happens to be subscribed.
    private var isUpdating = false

    /// The most recent fix, replayed to new subscribers so a late observer is
    /// not left blank until the device next moves.
    private var lastKnownCoordinate: Coordinate?

    init(accuracy: CLLocationAccuracy = kCLLocationAccuracyHundredMeters) {
        self.manager = CLLocationManager()
        super.init()
        manager.desiredAccuracy = accuracy
        manager.delegate = self
    }

    // MARK: Authorization

    nonisolated func authorizationStatus() async -> LocationAuthorization {
        await MainActor.run { LocationAuthorization(manager.authorizationStatus) }
    }

    @discardableResult
    nonisolated func requestWhenInUseAuthorization() async -> LocationAuthorization {
        let current = await authorizationStatus()
        // Only `.notDetermined` can produce a prompt; anything else is final and
        // would otherwise leave the continuation suspended forever.
        guard current == .notDetermined else { return current }

        return await withCheckedContinuation { continuation in
            Task { @MainActor in
                authorizationContinuations.append(continuation)
                manager.requestWhenInUseAuthorization()
            }
        }
    }

    // MARK: One-shot fix

    nonisolated func currentLocation() async throws -> Coordinate {
        let status = await authorizationStatus()
        guard !status.isDenied else { throw LocationError.authorizationDenied }

        if status == .notDetermined {
            let granted = await requestWhenInUseAuthorization()
            guard granted.isAuthorized else { throw LocationError.authorizationDenied }
        }

        // A cached fix avoids powering up the hardware for the common case.
        if let cached = await MainActor.run(body: { manager.location }),
           let coordinate = try? Coordinate(cached) {
            return coordinate
        }

        return try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                fixContinuations.append(continuation)
                manager.requestLocation()
            }
        }
    }

    // MARK: Continuous updates

    nonisolated func startUpdatingLocation() async {
        await MainActor.run {
            guard !isUpdating else { return }   // idempotent
            isUpdating = true
            manager.startUpdatingLocation()
        }
    }

    nonisolated func stopUpdatingLocation() async {
        await MainActor.run {
            guard isUpdating else { return }    // safe when never started
            isUpdating = false
            manager.stopUpdatingLocation()
        }
    }

    /// `nonisolated` so the stream can be created from any actor. The subscriber
    /// bookkeeping it performs is hopped onto the main actor.
    nonisolated func locationUpdates() -> AsyncThrowingStream<Coordinate, Error> {
        AsyncThrowingStream { continuation in
            let id = UUID()

            Task { @MainActor in
                self.streamContinuations[id] = continuation
                // Replay the latest fix so a subscriber joining an in-flight
                // session gets a value immediately.
                if let last = self.lastKnownCoordinate {
                    continuation.yield(last)
                }
            }

            // Removing the subscriber on cancellation stops this stream leaking
            // for the app's lifetime. The hardware is left running, because only
            // `stopUpdatingLocation()` owns that decision.
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in self.streamContinuations.removeValue(forKey: id) }
            }
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationManager: CLLocationManagerDelegate {

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = LocationAuthorization(manager.authorizationStatus)
        Task { @MainActor in
            // `.notDetermined` fires before the user has answered; callers
            // waiting on the prompt should keep waiting.
            guard status != .notDetermined else { return }
            let waiting = authorizationContinuations
            authorizationContinuations.removeAll()
            waiting.forEach { $0.resume(returning: status) }
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let latest = locations.last,
              let coordinate = try? Coordinate(latest) else { return }

        Task { @MainActor in
            lastKnownCoordinate = coordinate

            let waiting = fixContinuations
            fixContinuations.removeAll()
            waiting.forEach { $0.resume(returning: coordinate) }

            for continuation in streamContinuations.values {
                continuation.yield(coordinate)
            }
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        let mapped: LocationError = (error as? CLError)?.code == .denied
            ? .authorizationDenied
            : .locationUnavailable

        Task { @MainActor in
            let waiting = fixContinuations
            fixContinuations.removeAll()
            waiting.forEach { $0.resume(throwing: mapped) }
            // Streams deliberately stay alive: a transient failure should not
            // permanently end an observer's sequence.
        }
    }
}

// MARK: - CoreLocation bridging

private extension LocationAuthorization {
    init(_ status: CLAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .restricted: self = .restricted
        case .denied: self = .denied
        case .authorizedWhenInUse: self = .whenInUse
        case .authorizedAlways: self = .always
        @unknown default: self = .notDetermined
        }
    }
}

private extension Coordinate {
    /// Rejects the invalid fixes CoreLocation can emit before it has a lock.
    init(_ location: CLLocation) throws {
        try self.init(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
    }
}
