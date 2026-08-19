//
//  MainCoordinator.swift
//  ShootMap
//
//  Created by Septuagint Murito on 8/15/26.
//

import Foundation
import Observation

// MARK: - Routes

/// Destinations reachable inside the authenticated flow.
///
/// The map is the flow's root, so it has no case — an empty `path` *is* the map.
/// Create/Edit are modal, but still routes so one enum describes the whole flow.
nonisolated enum MainRoute: RouteRepresentable {
    /// Shared by both roles.
    case sessionDetail(sessionId: String)
    /// Photographer only. Carries the pin the composer should open with, so the
    /// selected location survives the hop from map to form.
    case createSession(coordinate: Coordinate?)
    /// Photographer only.
    case editSession(PhotoSession)
    /// The signed-in photographer's own sessions.
    case mySessions
}

/// Which map sits at the bottom of the stack. Derived from the user's role,
/// never chosen by a view.
nonisolated enum MainRoot: Hashable, Sendable {
    case viewerMap
    case photographerMap
}

/// Why the main flow is handing control back to `AppCoordinator`.
///
/// A named type rather than `Void` so new outcomes (account deleted, session
/// expired) can be added without changing the callback's shape.
nonisolated enum MainFlowOutcome: Hashable, Sendable {
    case signOutRequested
}

// MARK: - Dependencies

/// What the main flow needs to build its child ViewModels.
///
/// Protocol-typed so no Firestore or SwiftData type is ever named here, and so
/// the flow is constructible in tests with stubs.
nonisolated protocol MainFlowDependencies: Sendable {
    var sessionService: any PhotoSessionSyncServiceProtocol { get }
    /// Cache reads for the viewer map and detail screens.
    var localSessionRepository: any LocalPhotoSessionRepositoryProtocol { get }
    /// Remote reads/writes for authoring and detail refresh.
    var remoteSessionRepository: any PhotoSessionRepositoryProtocol { get }
    /// Needed by the photographer map to centre on the user.
    var locationManager: any LocationManagerProtocol { get }
    /// Identifies the publishing photographer when composing a session.
    var authRepository: any AuthRepositoryProtocol { get }
}

// MARK: - Coordinator

/// Owns navigation for the authenticated flow, for both roles.
///
/// Holds all navigation state (`path`, `presentedRoute`, `root`) so ViewModels
/// hold none. ViewModels call intent methods — `showSessionDetail(id:)` — and
/// never touch the stack. Nothing here reads or writes data; Firebase and
/// SwiftData are reached only by child ViewModels, through protocols.
@MainActor
@Observable
final class MainCoordinator: RouterProtocol, FlowCompleting {

    // MARK: Navigation state

    var path: [MainRoute] = []
    var presentedRoute: PresentedRoute<MainRoute>?

    /// Root screen for this session, fixed by the user's role at construction.
    let root: MainRoot

    // MARK: Flow completion

    /// Fired when the flow wants to hand control back. `AppCoordinator` decides
    /// what to do — this coordinator only reports the request.
    var onFinish: ((MainFlowOutcome) -> Void)?

    // MARK: Dependencies

    /// The signed-in user. Read for role-based routing only.
    private(set) var user: User

    /// Passed to child ViewModels at construction; never called here.
    let dependencies: any MainFlowDependencies

    // MARK: Init

    init(user: User, dependencies: any MainFlowDependencies) {
        self.user = user
        self.dependencies = dependencies
        self.root = user.role.canPublishSessions ? .photographerMap : .viewerMap
    }

    // MARK: Lifecycle

    func start() {
        popToRoot()
        dismiss()
    }

    // MARK: Role capability
    //
    // Reads the capability the domain already models — it does not re-derive
    // permission rules. Used to keep photographer-only destinations unreachable
    // from a viewer session.

    var canPublishSessions: Bool { user.role.canPublishSessions }

    // MARK: Shared navigation intent

    func showSessionDetail(sessionId: String) {
        push(.sessionDetail(sessionId: sessionId))
    }

    /// Convenience for call sites that already hold the session.
    func showSessionDetail(for session: PhotoSession) {
        showSessionDetail(sessionId: session.id)
    }

    func goBack() {
        pop()
    }

    func returnToMap() {
        popToRoot()
    }

    // MARK: Photographer-only navigation intent
    //
    // Guarded so a viewer can never land on an authoring screen, even if a
    // stale view or a deep link asks for one.

    /// Opens the composer, optionally seeded with the pin the photographer
    /// dropped on the map.
    func showCreateSession(at coordinate: Coordinate?) {
        guard canPublishSessions else { return }
        present(.createSession(coordinate: coordinate), style: .fullScreenCover)
    }

    /// Opens the composer with no location chosen yet.
    func showCreateSession() {
        showCreateSession(at: nil)
    }

    func showEditSession(_ session: PhotoSession) {
        guard canPublishSessions, session.photographerId == user.id else { return }
        present(.editSession(session), style: .fullScreenCover)
    }

    func showMySessions() {
        guard canPublishSessions else { return }
        push(.mySessions)
    }

    /// Called by the create/edit ViewModel once its repository work succeeded.
    /// The coordinator only closes the editor and reveals the result.
    func sessionEditingDidFinish(with session: PhotoSession?) {
        dismiss()
        if let session {
            showSessionDetail(for: session)
        }
    }

    func cancelSessionEditing() {
        dismiss()
    }

    // MARK: Session lifecycle

    /// Keeps role-derived routing honest if the profile changes mid-session
    /// (e.g. a viewer upgrades to photographer). `root` is intentionally fixed —
    /// changing it requires restarting the flow from `AppCoordinator`.
    func updateUser(_ user: User) {
        self.user = user
        if !user.role.canPublishSessions {
            closePhotographerOnlyDestinations()
        }
    }

    func requestSignOut() {
        onFinish?(.signOutRequested)
    }

    // MARK: Private

    private func closePhotographerOnlyDestinations() {
        if let presented = presentedRoute {
            switch presented.route {
            case .createSession, .editSession:
                dismiss()
            case .sessionDetail, .mySessions:
                break
            }
        }
        path.removeAll { route in
            switch route {
            case .createSession, .editSession, .mySessions: true
            case .sessionDetail: false
            }
        }
    }
}
