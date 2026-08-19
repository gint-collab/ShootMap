//
//  CreateSessionViewModel.swift
//  ShootMap
//
//  Created by Septuagint Murito on 8/19/26.
//

import Foundation
import Observation

/// Composes and publishes a new photo session.
///
/// Imports only `Foundation` and `Observation` — no MapKit, no Firebase, no
/// SwiftData, no SwiftUI. Every dependency is a protocol, so the whole flow is
/// exercisable with plain stubs.
@MainActor
@Observable
final class CreateSessionViewModel {

    // MARK: - Form state

    /// Where the session will happen. Pre-filled from the map pin; already
    /// range-validated by `Coordinate`'s throwing init, so it cannot be invalid.
    var selectedCoordinate: Coordinate?

    /// Calendar day of the shoot. Changing it re-anchors the times, so the
    /// session can never end up scheduled across two different days.
    var date: Date {
        didSet { realignTimesWithDate(previous: oldValue) }
    }

    var startTime: Date
    var endTime: Date

    // MARK: - Status

    private(set) var isSaving = false
    private(set) var errorMessage: String?

    // MARK: - Derived

    /// Whether the form is complete enough to attempt a save. Mirrors the domain
    /// rules but is only an affordance — `save()` re-validates authoritatively.
    var canSave: Bool {
        !isSaving && validationMessage == nil
    }

    /// Why the form cannot be published yet, or `nil` when it can.
    ///
    /// Surfaced so a disabled Publish button always explains itself — an
    /// unexplained dead button is indistinguishable from a broken one.
    var validationMessage: String? {
        guard selectedCoordinate != nil else {
            return "Choose a location on the map before publishing."
        }
        do {
            try preflightSession().validate(calendar: calendar)
            return nil
        } catch let error as DomainValidationError {
            return PhotoSessionError.invalid(error).errorDescription
        } catch {
            return "This session isn't valid yet."
        }
    }

    var hasLocation: Bool { selectedCoordinate != nil }

    /// Length of the shoot, for display.
    var duration: TimeInterval { endTime.timeIntervalSince(startTime) }

    // MARK: - Dependencies

    /// The write slice of the session repository — this screen creates sessions
    /// and never reads collections. A `PhotoSessionRepositoryProtocol` satisfies it.
    private let sessionRepository: any PhotoSessionWriting

    /// Read-only auth: the ViewModel needs to know *who* is publishing, and must
    /// not be able to sign anyone in or out.
    private let authRepository: any AuthSessionProviding

    /// `weak` because the coordinator owns this ViewModel.
    private weak var coordinator: (any MainCoordinatorProtocol)?

    /// Injected so date arithmetic is deterministic in tests.
    private let calendar: Calendar

    // MARK: - Init

    init(
        selectedCoordinate: Coordinate? = nil,
        sessionRepository: any PhotoSessionWriting,
        authRepository: any AuthSessionProviding,
        coordinator: (any MainCoordinatorProtocol)? = nil,
        calendar: Calendar = .current,
        now: Date = .now
    ) {
        self.selectedCoordinate = selectedCoordinate
        self.sessionRepository = sessionRepository
        self.authRepository = authRepository
        self.coordinator = coordinator
        self.calendar = calendar

        // Default to a one-hour shoot starting at the next whole hour, so the
        // form opens in a state that already satisfies the domain rules.
        let start = calendar.nextHour(after: now)
        self.date = calendar.startOfDay(for: start)
        self.startTime = start
        self.endTime = start.addingTimeInterval(60 * 60)
    }

    func setCoordinator(_ coordinator: any MainCoordinatorProtocol) {
        self.coordinator = coordinator
    }

    // MARK: - Editing

    func select(coordinate: Coordinate) {
        selectedCoordinate = coordinate
        errorMessage = nil
    }

    /// Accepts raw values from a map gesture and validates before storing, so an
    /// out-of-range coordinate can never reach the form.
    func selectCoordinate(latitude: Double, longitude: Double) {
        do {
            select(coordinate: try Coordinate(latitude: latitude, longitude: longitude))
        } catch {
            selectedCoordinate = nil
            errorMessage = "That location isn't valid. Pick a different spot on the map."
        }
    }

    /// Keeps `endTime` after `startTime` while the user is still editing, rather
    /// than letting them build an invalid range and only learning about it on save.
    func startTimeDidChange() {
        errorMessage = nil
        if endTime <= startTime {
            endTime = startTime.addingTimeInterval(60 * 60)
        }
    }

    func endTimeDidChange() {
        errorMessage = nil
    }

    func dismissError() {
        errorMessage = nil
    }

    // MARK: - Save

    /// Validates, builds the domain model, publishes it, and reports success to
    /// the coordinator. Never navigates on failure.
    func save() async {
        guard !isSaving else { return }

        errorMessage = nil
        isSaving = true
        defer { isSaving = false }

        do {
            guard let author = await authRepository.currentUser() else {
                throw PhotoSessionError.notAuthenticated
            }
            guard author.canPublishSessions else {
                throw PhotoSessionError.notPermittedToPublish
            }

            let session = try buildSession(id: UUID().uuidString, author: author)

            // Domain validation runs before the network call, so an invalid
            // session is rejected locally instead of costing a round trip.
            do {
                try session.validate(calendar: calendar)
            } catch let error as DomainValidationError {
                throw PhotoSessionError.invalid(error)
            }

            let stored = try await sessionRepository.publish(session)

            // Only now, after the repository confirmed the write, is navigation
            // requested. The coordinator decides what "finished" looks like.
            coordinator?.sessionEditingDidFinish(with: stored)

        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Couldn't publish your session. Please try again."
        }
    }

    func cancel() {
        coordinator?.cancelSessionEditing()
    }

    // MARK: - Private

    /// Assembles the domain model from form state.
    ///
    /// `photographerId` and the page details come from the authenticated user,
    /// never from the form — the repository overwrites them server-side anyway,
    /// so deriving them here keeps the two in agreement.
    private func buildSession(id: String, author: User) throws -> PhotoSession {
        guard let coordinate = selectedCoordinate else {
            throw PhotoSessionError.invalid(.invalidLatitude(.nan))
        }

        return PhotoSession(
            id: id,
            photographerId: author.id,
            photographerName: author.displayName,
            facebookPageName: author.facebookPageName,
            facebookPageURL: author.facebookPageURL,
            coordinate: coordinate,
            date: calendar.startOfDay(for: date),
            startTime: startTime,
            endTime: endTime,
            status: .scheduled
        )
    }

    /// Moves the times onto the newly chosen day, preserving the hour and minute
    /// the user already picked.
    private func realignTimesWithDate(previous: Date) {
        guard !calendar.isDate(previous, inSameDayAs: date) else { return }
        startTime = calendar.moving(startTime, ontoDayOf: date) ?? startTime
        endTime = calendar.moving(endTime, ontoDayOf: date) ?? endTime
        if endTime <= startTime {
            endTime = startTime.addingTimeInterval(60 * 60)
        }
    }

    /// Stand-in author used only by validation, so the form can be checked
    /// synchronously without an auth round trip. Never persisted.
    private var previewAuthor: User {
        User(id: "preflight", email: "preflight@shootmap.app", displayName: "Preflight")
    }

    /// The session the form currently describes, attributed to a stand-in
    /// author. Throws only if no location has been chosen.
    private func preflightSession() throws -> PhotoSession {
        try buildSession(id: "preflight", author: previewAuthor)
    }
}

// MARK: - Date helpers

private extension Calendar {
    func nextHour(after date: Date) -> Date {
        let next = self.date(byAdding: .hour, value: 1, to: date) ?? date
        return self.date(
            bySettingHour: component(.hour, from: next),
            minute: 0,
            second: 0,
            of: next
        ) ?? next
    }

    /// Rebuilds `time` on the calendar day of `day`, keeping hour and minute.
    func moving(_ time: Date, ontoDayOf day: Date) -> Date? {
        let components = dateComponents([.hour, .minute], from: time)
        return self.date(
            bySettingHour: components.hour ?? 0,
            minute: components.minute ?? 0,
            second: 0,
            of: startOfDay(for: day)
        )
    }
}
