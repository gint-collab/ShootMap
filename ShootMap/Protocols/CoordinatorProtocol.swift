//
//  CoordinatorProtocol.swift
//  ShootMap
//
//  Created by Septuagint Murito on 8/15/26.
//

import SwiftUI

// MARK: - Route

/// A destination a coordinator can navigate to.
///
/// Declare conforming enums as `nonisolated` — the module uses default
/// main-actor isolation, and routes are inert value types that should stay
/// actor-agnostic so they work from deep links and tests:
///
///     nonisolated enum MapRoute: RouteRepresentable {
///         case sessionDetail(sessionId: String)
///         case photographerProfile(userId: String)
///     }
nonisolated protocol RouteRepresentable: Hashable, Sendable {}

// MARK: - Modal presentation

/// How a destination is shown when it is not pushed onto the stack.
nonisolated enum PresentationStyle: Hashable, Sendable {
    case sheet
    case fullScreenCover
}

/// A route awaiting modal presentation.
///
/// Carries its own identity so presenting the *same* route twice in a row still
/// re-triggers SwiftUI's `.sheet(item:)` / `.fullScreenCover(item:)`.
nonisolated struct PresentedRoute<Route: RouteRepresentable>: Identifiable, Hashable, Sendable {
    let id: UUID
    let route: Route
    let style: PresentationStyle

    init(route: Route, style: PresentationStyle, id: UUID = UUID()) {
        self.id = id
        self.route = route
        self.style = style
    }
}

// MARK: - Router (the ViewModel-facing surface)

/// The *only* navigation surface a ViewModel is allowed to see.
///
/// ViewModels never build views, never touch `NavigationStack`, and never know
/// which coordinator is behind this — they just express intent ("show the
/// session detail"). Uses a primary associated type so a ViewModel can hold a
/// plain existential and be tested with a trivial spy:
///
///     final class MapViewModel {
///         private let router: any RouterProtocol<MapRoute>
///     }
@MainActor
protocol RouterProtocol<Route>: AnyObject {
    associatedtype Route: RouteRepresentable

    /// Ordered push-navigation stack. Readable so tests can assert on it.
    var path: [Route] { get set }

    /// Currently presented modal route, if any.
    var presentedRoute: PresentedRoute<Route>? { get set }

    func push(_ route: Route)
    func pop()
    func popToRoot()

    func present(_ route: Route, style: PresentationStyle)
    func dismiss()
}

// MARK: - Router default behaviour

@MainActor
extension RouterProtocol {
    var isAtRoot: Bool { path.isEmpty }
    var currentRoute: Route? { path.last }
    var isPresentingModal: Bool { presentedRoute != nil }

    func push(_ route: Route) {
        path.append(route)
    }

    func pop() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    func popToRoot() {
        path.removeAll()
    }

    func present(_ route: Route, style: PresentationStyle = .sheet) {
        presentedRoute = PresentedRoute(route: route, style: style)
    }

    func dismiss() {
        presentedRoute = nil
    }

    /// Pops back to a specific route, doing nothing if it is not on the stack.
    func pop(to route: Route) {
        guard let index = path.lastIndex(of: route) else { return }
        path.removeSubrange(path.index(after: index)..<path.endIndex)
    }

    /// Replaces the whole stack in one update — avoids intermediate animations.
    func setPath(_ routes: [Route]) {
        path = routes
    }
}

// MARK: - Coordinator

/// Owns a navigation flow: the stack, the modal state, and the mapping from a
/// route to the view that represents it.
///
/// This is the view-facing half of the contract. It deliberately extends
/// `RouterProtocol` so a coordinator can be handed to a ViewModel as
/// `any RouterProtocol<Route>` — the ViewModel then physically cannot build
/// views or reach navigation internals.
///
/// Contains no Firebase, SwiftData, or repository types.
@MainActor
protocol CoordinatorProtocol: RouterProtocol {
    /// View produced for a pushed destination.
    associatedtype Destination: View
    /// View shown at the bottom of this flow's stack.
    associatedtype Root: View
    /// View produced for a modally presented route.
    associatedtype Modal: View = Destination

    /// Entry point — seeds initial state before the flow is shown.
    func start()

    /// Root of this flow's `NavigationStack`.
    @ViewBuilder
    func rootView() -> Root

    /// Destination for a pushed route. Wired to `.navigationDestination(for:)`.
    @ViewBuilder
    func view(for route: Route) -> Destination

    /// Destination for a modally presented route.
    /// Defaults to the same builder used for pushes.
    @ViewBuilder
    func modalView(for route: Route) -> Modal
}

@MainActor
extension CoordinatorProtocol where Modal == Destination {
    func modalView(for route: Route) -> Destination {
        view(for: route)
    }
}

@MainActor
extension CoordinatorProtocol {
    /// No-op default so simple flows need not implement it.
    func start() {}
}

// MARK: - Flow completion

/// A child flow that reports back to its parent — e.g. the auth flow finishing
/// and handing control to the main app flow. Kept separate so flows that never
/// terminate are not forced to model an output.
@MainActor
protocol FlowCompleting<Output>: AnyObject {
    associatedtype Output

    var onFinish: ((Output) -> Void)? { get set }
}

// MARK: - SwiftUI plumbing

/// Renders any coordinator as a `NavigationStack` with push destinations and
/// both modal presentation styles already wired up.
///
/// Generic over the protocol, so it is written once here and *no* concrete
/// coordinator has to repeat this boilerplate:
///
///     CoordinatedStack(coordinator: mapCoordinator)
struct CoordinatedStack<C: CoordinatorProtocol & Observable>: View {
    @Bindable var coordinator: C

    var body: some View {
        NavigationStack(path: $coordinator.path) {
            coordinator.rootView()
                .navigationDestination(for: C.Route.self) { route in
                    coordinator.view(for: route)
                }
        }
        .sheet(item: sheetBinding) { presented in
            // Modals are presented in their own hierarchy, so a gesture attached
            // at the app root does not reach them — they opt in here instead.
            coordinator.modalView(for: presented.route)
                .dismissesKeyboardOnTap()
        }
        .fullScreenCover(item: fullScreenBinding) { presented in
            coordinator.modalView(for: presented.route)
                .dismissesKeyboardOnTap()
        }
        .task { coordinator.start() }
    }

    /// Splits the single `presentedRoute` into the two bindings SwiftUI needs,
    /// so only the matching modifier ever fires.
    private var sheetBinding: Binding<PresentedRoute<C.Route>?> {
        binding(for: .sheet)
    }

    private var fullScreenBinding: Binding<PresentedRoute<C.Route>?> {
        binding(for: .fullScreenCover)
    }

    private func binding(for style: PresentationStyle) -> Binding<PresentedRoute<C.Route>?> {
        Binding(
            get: {
                guard let presented = coordinator.presentedRoute, presented.style == style else { return nil }
                return presented
            },
            set: { newValue in
                // Only clear state this modifier actually owns.
                if newValue == nil, coordinator.presentedRoute?.style == style {
                    coordinator.presentedRoute = nil
                } else if let newValue {
                    coordinator.presentedRoute = newValue
                }
            }
        )
    }
}
