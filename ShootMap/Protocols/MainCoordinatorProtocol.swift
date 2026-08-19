//
//  MainCoordinatorProtocol.swift
//  ShootMap
//
//  Created by Septuagint Murito on 8/19/26.
//

import Foundation

/// The navigation vocabulary the authenticated screens need.
///
/// Exposes *intent* (`showCreateSession`) and never mechanism (`push` / `pop` /
/// `path`). A ViewModel holding this cannot reach the `NavigationStack`, cannot
/// build a view, and cannot know it is driving a `MainCoordinator` — so
/// "no navigation through NavigationStack" is a compile-time guarantee rather
/// than a convention.
///
/// `@MainActor` because navigation state is main-actor state; `AnyObject` so
/// ViewModels can hold it `weak` and avoid a retain cycle with the coordinator.
@MainActor
protocol MainCoordinatorProtocol: AnyObject {

    /// Whether the signed-in user may reach authoring screens. Read by
    /// ViewModels for presentation decisions; the coordinator enforces it anyway.
    var canPublishSessions: Bool { get }

    // MARK: Shared

    func showSessionDetail(sessionId: String)
    func showSessionDetail(for session: PhotoSession)
    func goBack()
    func returnToMap()

    // MARK: Photographer-only

    /// Open the session composer. Ignored for users who cannot publish.
    func showCreateSession()

    /// Open the editor for an existing session. Ignored unless the caller owns it.
    func showEditSession(_ session: PhotoSession)

    func showMySessions()

    /// Report that create/edit finished so the coordinator can close the editor.
    /// Called *after* the repository confirms success — this never saves anything.
    func sessionEditingDidFinish(with session: PhotoSession?)

    func cancelSessionEditing()

    // MARK: Session

    func requestSignOut()
}

// MARK: - Conformance

/// The concrete coordinator already speaks exactly this vocabulary, so adopting
/// the protocol adds no code — it only narrows what ViewModels can see.
extension MainCoordinator: MainCoordinatorProtocol {}
