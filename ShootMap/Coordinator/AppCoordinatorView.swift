//
//  AppCoordinatorView.swift
//  ShootMap
//
//  Created by Septuagint Murito on 8/20/26.
//

import SwiftUI

/// The app's root view: a pure function of `AppCoordinator.flow`.
///
/// It owns no navigation decisions — it renders whichever flow the coordinator
/// says is current, and hands each child flow to `CoordinatedStack`.
struct AppCoordinatorView: View {

    @State private var coordinator: AppCoordinator

    /// Builds child coordinators. Held here rather than inside `AppCoordinator`
    /// so that coordinator stays free of SwiftUI and of the dependency graph.
    private let container: AppDependencyContainer

    /// Child coordinators are cached per flow so navigation state survives a
    /// re-render. Rebuilding them every `body` evaluation would silently reset
    /// the user's stack.
    @State private var authCoordinator: AuthCoordinator?
    @State private var mainCoordinator: MainCoordinator?

    init(container: AppDependencyContainer) {
        self.container = container
        _coordinator = State(initialValue: container.makeAppCoordinator())
    }

    var body: some View {
        Group {
            switch coordinator.flow {
            case .launching:
                SplashView()

            case .authentication:
                CoordinatedStack(coordinator: authFlow())

            case let .main(user):
                CoordinatedStack(coordinator: mainFlow(for: user))
            }
        }
        .animation(.default, value: coordinator.flow)
        // Applied once here so every screen in every flow inherits it.
        .dismissesKeyboardOnTap()
        .task { coordinator.start() }
        .onDisappear { coordinator.stop() }
        .alert(
            "Couldn't sign out",
            isPresented: Binding(
                get: { coordinator.signOutFailed },
                set: { if !$0 { coordinator.dismissSignOutFailure() } }
            )
        ) {
            Button("OK", role: .cancel) { coordinator.dismissSignOutFailure() }
        } message: {
            Text("Please check your connection and try again.")
        }
    }

    // MARK: - Child flows

    private func authFlow() -> AuthCoordinator {
        if let authCoordinator { return authCoordinator }

        let created = container.makeAuthCoordinator()
        // The auth flow reports success upward; `AppCoordinator` reacts to the
        // auth stream itself, so nothing here forces a flow change.
        created.onFinish = { _ in }
        Task { @MainActor in authCoordinator = created }
        return created
    }

    private func mainFlow(for user: User) -> MainCoordinator {
        if let mainCoordinator, mainCoordinator.user.id == user.id {
            return mainCoordinator
        }

        let created = container.makeMainCoordinator(user: user)
        created.onFinish = { outcome in
            switch outcome {
            case .signOutRequested:
                Task { await coordinator.signOut() }
            }
        }
        Task { @MainActor in mainCoordinator = created }
        return created
    }
}

// MARK: - Splash

/// Shown while authentication state is still unresolved.
struct SplashView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("ShootMap")
                .font(.largeTitle.weight(.semibold))
            ProgressView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}
