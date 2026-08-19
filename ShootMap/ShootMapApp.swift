//
//  ShootMapApp.swift
//  ShootMap
//
//  Created by Septuagint Murito on 8/14/26.
//

import SwiftUI
import SwiftData

@main
struct ShootMapApp: App {

    /// The composition root. Built once at launch; everything downstream
    /// receives protocols, never concrete types.
    @State private var startup: StartupState

    init() {
        _startup = State(initialValue: Self.bootstrap())
    }

    var body: some Scene {
        WindowGroup {
            switch startup {
            case let .ready(container):
                AppCoordinatorView(container: container)
                    // Housekeeping, not user-facing: evict cache entries that
                    // have outlived the retention policy.
                    .task { try? await container.cleanUpCacheIfNeeded() }

            case let .failed(message):
                StartupFailureView(message: message)
            }
        }
    }

    // MARK: - Bootstrap

    /// Configures Firebase and builds the object graph.
    ///
    /// Returns a failure state instead of trapping: a missing plist or an
    /// unreadable store should show an explanatory screen, not crash on launch.
    @MainActor
    private static func bootstrap() -> StartupState {
        do {
            let firebase = FirebaseManager.shared
            try firebase.configure()

            let modelContainer = try AppDependencyContainer.makeModelContainer()

            return .ready(
                AppDependencyContainer.live(
                    firebase: firebase,
                    modelContainer: modelContainer
                )
            )
        } catch {
            let message = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            return .failed(message)
        }
    }
}

// MARK: - Startup state

/// Launch either produces a usable dependency graph or an explanation.
/// Modelling it this way keeps the impossible "ready but broken" state
/// unrepresentable.
enum StartupState {
    case ready(AppDependencyContainer)
    case failed(String)
}

// MARK: - Failure screen

struct StartupFailureView: View {
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label("ShootMap can't start", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        }
    }
}

// MARK: - Cache housekeeping

extension AppDependencyContainer {
    /// Applies the retention policy if the concrete sync service supports it.
    ///
    /// The protocol deliberately does not expose cleanup — it is an
    /// implementation concern, not something callers should orchestrate.
    func cleanUpCacheIfNeeded() async throws {
        guard let service = sessionService as? PhotoSessionSyncService else { return }
        try await service.cleanUpCache()
    }
}
