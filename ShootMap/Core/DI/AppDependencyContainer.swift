//
//  AppDependencyContainer.swift
//  ShootMap
//
//  Created by Septuagint Murito on 8/17/26.
//

import Foundation
import SwiftData

/// What the app needs in order to build any flow.
///
/// Composing the flow-scoped protocols means a coordinator keeps depending on
/// the narrow slice it actually uses (`AuthFlowDependencies`,
/// `MainFlowDependencies`) rather than on the whole container.
nonisolated protocol AppDependencies: AuthFlowDependencies, MainFlowDependencies {
    var authRepository: any AuthRepositoryProtocol { get }
    var sessionService: any PhotoSessionSyncServiceProtocol { get }
    var locationManager: any LocationManagerProtocol { get }
}

/// The composition root.
///
/// This is the **only** type in the app that names a concrete implementation.
/// Everything it hands out is protocol-typed, so ViewModels and coordinators
/// cannot reach Firebase, Firestore, SwiftData or CoreLocation even by accident.
///
/// Tests construct it through the designated `init`, passing mocks. Production
/// uses `live(...)`, which is the single place the real types are instantiated.
nonisolated final class AppDependencyContainer: AppDependencies {

    // MARK: Dependencies — protocol-typed, never concrete

    let authRepository: any AuthRepositoryProtocol
    let remoteSessionRepository: any PhotoSessionRepositoryProtocol
    let localSessionRepository: any LocalPhotoSessionRepositoryProtocol
    let sessionService: any PhotoSessionSyncServiceProtocol
    let locationManager: any LocationManagerProtocol

    // MARK: Init

    /// Designated initialiser: every collaborator is injected as a protocol.
    /// Swap any subset for a mock in tests without touching production code.
    init(
        authRepository: any AuthRepositoryProtocol,
        remoteSessionRepository: any PhotoSessionRepositoryProtocol,
        localSessionRepository: any LocalPhotoSessionRepositoryProtocol,
        sessionService: any PhotoSessionSyncServiceProtocol,
        locationManager: any LocationManagerProtocol
    ) {
        self.authRepository = authRepository
        self.remoteSessionRepository = remoteSessionRepository
        self.localSessionRepository = localSessionRepository
        self.sessionService = sessionService
        self.locationManager = locationManager
    }

    // MARK: Production graph

    /// Builds the real object graph.
    ///
    /// `FirebaseManager` is passed in rather than reached for statically, so an
    /// emulator-backed instance can be substituted wholesale in integration tests.
    ///
    /// - Important: `firebase.configure()` must already have succeeded.
    ///
    /// `@MainActor` because `LocationManager` wraps `CLLocationManager`, which
    /// requires a run loop. The composition root runs at launch anyway.
    @MainActor
    static func live(
        firebase: any FirebaseProviding,
        modelContainer: ModelContainer
    ) -> AppDependencyContainer {
        let authRepository = FirebaseAuthRepository(
            auth: firebase.auth,
            firestore: firebase.firestore
        )
        // The session repository needs the authenticated identity to stamp and
        // verify ownership. It receives the narrow `AuthSessionProviding` slice,
        // not the full auth repository.
        let remote = FirestorePhotoSessionRepository(
            firestore: firebase.firestore,
            sessionProvider: authRepository
        )
        let local = SwiftDataPhotoSessionRepository(modelContainer: modelContainer)
        let sync = PhotoSessionSyncService(remote: remote, local: local)

        return AppDependencyContainer(
            authRepository: authRepository,
            remoteSessionRepository: remote,
            localSessionRepository: local,
            sessionService: sync,
            locationManager: LocationManager()
        )
    }

    /// The cache store. Separate from `live` so tests can pass an in-memory
    /// container and leave the user's real database untouched.
    static func makeModelContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([PhotoSessionEntity.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

// MARK: - Coordinator factories

/// Coordinators are built here so no coordinator has to know how to construct
/// its own dependencies — it receives exactly the protocols it needs.
@MainActor
extension AppDependencyContainer {

    func makeAppCoordinator() -> AppCoordinator {
        AppCoordinator(authRepository: authRepository)
    }

    func makeAuthCoordinator() -> AuthCoordinator {
        // `self` satisfies `AuthFlowDependencies`, so the flow sees only
        // `authRepository` — not the session or location dependencies.
        AuthCoordinator(dependencies: self)
    }

    func makeMainCoordinator(user: User) -> MainCoordinator {
        MainCoordinator(user: user, dependencies: self)
    }
}
