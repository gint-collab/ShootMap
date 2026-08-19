//
//  PhotographerMapViewModel.swift
//  ShootMap
//
//  Created by Septuagint Murito on 8/19/26.
//

import Foundation
import Observation

/// Drives the photographer's map: permission, pin selection, and the entry point
/// to composing a session.
///
/// Imports only `Foundation` and `Observation` — no MapKit, no CoreLocation, no
/// Firebase, no SwiftData, no SwiftUI. Locations are the domain's `Coordinate`,
/// so the view converts to `CLLocationCoordinate2D` at the boundary and this type
/// stays testable without a simulator.
@MainActor
@Observable
final class PhotographerMapViewModel {

    // MARK: - State

    /// Where the camera should sit. `nil` until a location is resolved, so the
    /// view can show its own default rather than being forced to (0, 0).
    private(set) var userLocation: Coordinate?

    /// The pin the photographer has dropped, if any. Only ever set to a
    /// coordinate that passed domain validation.
    private(set) var selectedCoordinate: Coordinate?

    /// The photographer's own sessions, for showing existing pins alongside the
    /// new one. Loaded lazily — the map is usable before this arrives.
    private(set) var mySessions: [PhotoSession] = []

    private(set) var authorization: LocationAuthorization = .notDetermined
    private(set) var isLoadingSessions = false

    /// Message for the most recent failure, or `nil`. The ViewModel owns the
    /// wording so the view contains no error interpretation.
    private(set) var errorMessage: String?

    // MARK: - Derived

    var hasSelection: Bool { selectedCoordinate != nil }

    /// Whether the "Create session here" affordance should be offered.
    var canCreateSession: Bool {
        hasSelection && (coordinator?.canPublishSessions ?? false)
    }

    /// True when location was refused, so the view can offer a Settings prompt.
    var isLocationDenied: Bool { authorization.isDenied }

    /// Whether the map may render the blue user-location dot. Asking MapKit to
    /// show it without authorization produces a console warning and nothing else.
    var isLocationAvailable: Bool { authorization.isAuthorized }

    var shouldPromptForLocation: Bool { authorization == .notDetermined }

    // MARK: - Dependencies

    private let locationManager: any LocationManagerProtocol

    /// The read slice of the session repository. A `PhotoSessionRepositoryProtocol`
    /// satisfies this, but narrowing it here means this screen cannot publish,
    /// update or delete — only photographer authoring screens get that power.
    private let sessionRepository: any PhotoSessionReading

    private let photographerId: String

    /// `weak` because the coordinator owns this ViewModel; a strong reference
    /// back would retain both for the app's lifetime.
    private weak var coordinator: (any MainCoordinatorProtocol)?

    // MARK: - Init

    init(
        photographerId: String,
        locationManager: any LocationManagerProtocol,
        sessionRepository: any PhotoSessionReading,
        coordinator: (any MainCoordinatorProtocol)? = nil
    ) {
        self.photographerId = photographerId
        self.locationManager = locationManager
        self.sessionRepository = sessionRepository
        self.coordinator = coordinator
    }

    /// Set separately when the coordinator builds the view after the ViewModel.
    func setCoordinator(_ coordinator: any MainCoordinatorProtocol) {
        self.coordinator = coordinator
    }

    // MARK: - Lifecycle

    /// Call from the view's `.task`. Safe to call repeatedly.
    func onAppear() async {
        await requestLocationPermission()
        await loadMySessions()
    }

    // MARK: - Location

    /// Asks for permission and, if granted, centres the map on the user.
    /// Requesting when already decided is a no-op inside the manager, so this is
    /// safe to call on every appearance.
    func requestLocationPermission() async {
        authorization = await locationManager.requestWhenInUseAuthorization()

        guard authorization.isAuthorized else {
            // Not an error: the map still works, the photographer just has to
            // pan to the location manually.
            return
        }
        await refreshUserLocation()
    }

    func refreshUserLocation() async {
        do {
            userLocation = try await locationManager.currentLocation()
        } catch {
            // A missing fix must not block pin selection, so this is silent
            // rather than surfaced as a failure.
            userLocation = nil
        }
    }

    /// Centres the pin on the user's current position.
    func selectCurrentLocation() async {
        await refreshUserLocation()
        if let userLocation {
            select(coordinate: userLocation)
        }
    }

    // MARK: - Pin selection

    /// Selects a tapped point, validating it before it becomes state.
    ///
    /// Takes raw `Double`s because map gestures hand back raw values; this is the
    /// single place they are checked, so an out-of-range or NaN coordinate can
    /// never reach `selectedCoordinate` — and therefore never reach a
    /// `PhotoSession`.
    func selectCoordinate(latitude: Double, longitude: Double) {
        do {
            select(coordinate: try Coordinate(latitude: latitude, longitude: longitude))
        } catch {
            selectedCoordinate = nil
            errorMessage = "That location isn't valid. Try tapping somewhere else on the map."
        }
    }

    func select(coordinate: Coordinate) {
        selectedCoordinate = coordinate
        errorMessage = nil
    }

    func clearSelection() {
        selectedCoordinate = nil
        errorMessage = nil
    }

    // MARK: - Navigation intent
    //
    // Every method here delegates to the coordinator. The ViewModel decides
    // *when* to navigate; the coordinator decides what that means.

    /// Opens the composer for the currently selected pin.
    func createSessionAtSelectedLocation() {
        guard selectedCoordinate != nil else {
            errorMessage = "Tap the map to choose where you'll be shooting."
            return
        }
        coordinator?.showCreateSession()
    }

    func showSessionDetail(for session: PhotoSession) {
        coordinator?.showSessionDetail(for: session)
    }

    func editSession(_ session: PhotoSession) {
        coordinator?.showEditSession(session)
    }

    func showMySessions() {
        coordinator?.showMySessions()
    }

    // MARK: - Data

    /// Loads the photographer's own sessions so existing pins render alongside
    /// the new selection. Failure leaves whatever was already loaded in place.
    func loadMySessions() async {
        guard !isLoadingSessions else { return }
        isLoadingSessions = true
        defer { isLoadingSessions = false }

        do {
            mySessions = try await sessionRepository.sessions(
                matching: .authored(by: photographerId)
            )
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Couldn't load your sessions."
        }
    }

    /// Call after publishing or editing so the map reflects the change.
    func reloadAfterChange() async {
        await loadMySessions()
    }

    func dismissError() {
        errorMessage = nil
    }
}
