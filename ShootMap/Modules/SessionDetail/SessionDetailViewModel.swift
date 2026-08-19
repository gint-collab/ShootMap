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

    // MARK: - Derived

    var isMissing: Bool { session == nil && !isLoading }

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

    /// `weak` because the coordinator owns this ViewModel.
    private weak var coordinator: (any MainCoordinatorProtocol)?

    // MARK: - Init

    init(
        sessionId: String,
        localRepository: any LocalPhotoSessionRepositoryProtocol,
        remoteRepository: any PhotoSessionReading,
        coordinator: (any MainCoordinatorProtocol)? = nil
    ) {
        self.sessionId = sessionId
        self.localRepository = localRepository
        self.remoteRepository = remoteRepository
        self.coordinator = coordinator
    }

    /// Convenience for call sites that already hold the session, so the detail
    /// screen renders with no load at all.
    convenience init(
        session: PhotoSession,
        localRepository: any LocalPhotoSessionRepositoryProtocol,
        remoteRepository: any PhotoSessionReading,
        coordinator: (any MainCoordinatorProtocol)? = nil
    ) {
        self.init(
            sessionId: session.id,
            localRepository: localRepository,
            remoteRepository: remoteRepository,
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

    // MARK: - Navigation intent

    func goBack() {
        coordinator?.goBack()
    }
}
