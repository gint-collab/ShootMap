//
//  SessionDetailViewModel.swift
//  ShootMap
//
//  Created by Septuagint Murito on 8/19/26.
//

import Foundation
import Observation

/// Supplies a single `PhotoSession` to `SessionDetailView`.
///
/// Cache-first, like the map: the locally cached copy is shown immediately, then
/// refreshed from the remote source. A refresh failure leaves the cached session
/// on screen rather than emptying the view.
///
/// Imports only `Foundation` and `Observation` — no Firebase, no SwiftData,
/// no MapKit, no SwiftUI.
@MainActor
@Observable
final class SessionDetailViewModel {

    // MARK: - State

    /// The session being displayed. `nil` until loaded, or if it no longer exists.
    private(set) var session: PhotoSession?

    private(set) var isLoading = false
    private(set) var errorMessage: String?

    /// A status change is in flight.
    private(set) var isUpdatingStatus = false

    // MARK: - Derived

    var isMissing: Bool { session == nil && !isLoading }

    /// Whether the signed-in user authored this session, and may therefore
    /// change its status. Ownership is re-checked server-side by the repository
    /// and by Firestore rules — this only decides what to show.
    var isOwner: Bool {
        guard let session else { return false }
        return session.photographerId == currentUserId
    }

    /// Statuses this session may legally move to next.
    ///
    /// Derived from the domain's state machine rather than a hand-written list,
    /// so the UI can never offer a transition the model would reject.
    var availableStatusTransitions: [SessionStatus] {
        guard let session, isOwner else { return [] }
        return SessionStatus.allCases.filter { session.status.canTransition(to: $0) }
    }

    var canChangeStatus: Bool { !availableStatusTransitions.isEmpty && !isUpdatingStatus }

    /// Whether the photographer published a page worth opening.
    var facebookPageURL: URL? { session?.facebookPageURL }

    var hasFacebookPage: Bool {
        session?.facebookPageURL != nil || session?.facebookPageName != nil
    }

    /// Display name for the page, falling back to the URL's host.
    var facebookPageTitle: String? {
        session?.facebookPageName ?? session?.facebookPageURL?.host()
    }

    // MARK: - Dependencies

    private let sessionId: String

    /// Local cache read — the instant first paint.
    private let localRepository: any LocalPhotoSessionRepositoryProtocol

    /// Remote read slice, for refreshing the cached copy.
    private let remoteRepository: any PhotoSessionReading

    /// Write slice, used only to change status. Separate from the reader so the
    /// dependency states plainly what this screen is allowed to mutate.
    private let sessionWriter: any PhotoSessionWriting

    /// The signed-in user, for the ownership check.
    private let currentUserId: String

    /// `weak` because the coordinator owns this ViewModel.
    private weak var coordinator: (any MainCoordinatorProtocol)?

    // MARK: - Init

    init(
        sessionId: String,
        localRepository: any LocalPhotoSessionRepositoryProtocol,
        remoteRepository: any PhotoSessionReading,
        sessionWriter: any PhotoSessionWriting,
        currentUserId: String = "",
        coordinator: (any MainCoordinatorProtocol)? = nil
    ) {
        self.sessionId = sessionId
        self.localRepository = localRepository
        self.remoteRepository = remoteRepository
        self.sessionWriter = sessionWriter
        self.currentUserId = currentUserId
        self.coordinator = coordinator
    }

    /// Convenience for call sites that already hold the session, so the detail
    /// screen renders with no load at all.
    convenience init(
        session: PhotoSession,
        localRepository: any LocalPhotoSessionRepositoryProtocol,
        remoteRepository: any PhotoSessionReading,
        sessionWriter: any PhotoSessionWriting,
        currentUserId: String = "",
        coordinator: (any MainCoordinatorProtocol)? = nil
    ) {
        self.init(
            sessionId: session.id,
            localRepository: localRepository,
            remoteRepository: remoteRepository,
            sessionWriter: sessionWriter,
            currentUserId: currentUserId,
            coordinator: coordinator
        )
        self.session = session
    }

    func setCoordinator(_ coordinator: any MainCoordinatorProtocol) {
        self.coordinator = coordinator
    }

    // MARK: - Loading

    /// Call from the view's `.task`.
    func load() async {
        isLoading = session == nil
        defer { isLoading = false }

        // 1. Cached copy first.
        if session == nil, let cached = try? await localRepository.session(id: sessionId) {
            session = cached
        }

        // 2. Then refresh from the source of truth.
        do {
            if let fresh = try await remoteRepository.session(id: sessionId) {
                session = fresh
            } else if session != nil {
                // Deleted remotely while the user was looking at it.
                session = nil
                errorMessage = "This session was removed by the photographer."
            }
        } catch {
            // Keep the cached copy; only report if there is nothing to show.
            if session == nil {
                errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? "Couldn't load this session."
            }
        }
    }

    func refresh() async {
        await load()
    }

    func dismissError() {
        errorMessage = nil
    }

    // MARK: - Status changes

    /// Moves the session to `next`, if the transition is legal and the caller
    /// owns it.
    ///
    /// The domain's `transitioned(to:)` is the gate: an illegal move is refused
    /// here rather than being sent to the server and rejected there.
    func updateStatus(to next: SessionStatus) async {
        guard let current = session else { return }
        guard isOwner else {
            errorMessage = PhotoSessionError.notSessionOwner.errorDescription
            return
        }
        guard let updated = current.transitioned(to: next) else {
            errorMessage = "That status change isn't allowed from \(current.status.rawValue)."
            return
        }

        errorMessage = nil
        isUpdatingStatus = true
        defer { isUpdatingStatus = false }

        do {
            // Remote first: the cache must never claim a status the server
            // rejected, so a failure leaves no local trace.
            try await sessionWriter.updateStatus(next, forSessionId: current.id)
            session = updated
            // Best-effort cache refresh — the map reflects it on the next sync
            // regardless, so a cache failure is not worth surfacing.
            try? await localRepository.upsert([updated], syncedAt: .now)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Couldn't update the session status."
        }
    }

    // MARK: - Navigation intent

    func goBack() {
        coordinator?.goBack()
    }
}
