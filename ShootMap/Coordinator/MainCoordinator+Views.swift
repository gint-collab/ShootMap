//
//  MainCoordinator+Views.swift
//  ShootMap
//
//  Created by Septuagint Murito on 8/20/26.
//

import SwiftUI

/// Completes `MainCoordinator` into a full `CoordinatorProtocol`.
///
/// This is the single place a route becomes a screen, and the single place a
/// ViewModel is constructed with its dependencies — which is what keeps every
/// ViewModel free of knowledge about how its collaborators are built.
extension MainCoordinator: CoordinatorProtocol {

    /// Root is chosen by role, fixed at construction. A view never picks it.
    @ViewBuilder
    func rootView() -> some View {
        switch root {
        case .viewerMap:
            ViewerMapView(viewModel: makeViewerMapViewModel())
        case .photographerMap:
            PhotographerMapView(viewModel: makePhotographerMapViewModel())
        }
    }

    @ViewBuilder
    func view(for route: MainRoute) -> some View {
        switch route {
        case let .sessionDetail(sessionId):
            SessionDetailView(viewModel: makeSessionDetailViewModel(sessionId: sessionId))

        case let .createSession(coordinate):
            CreateSessionView(viewModel: makeCreateSessionViewModel(coordinate: coordinate))

        case let .editSession(session):
            CreateSessionView(viewModel: makeCreateSessionViewModel(coordinate: session.coordinate))

        case .mySessions:
            MySessionsView(viewModel: makePhotographerMapViewModel())
        }
    }

    // MARK: - ViewModel factories

    private func makeViewerMapViewModel() -> ViewerMapViewModel {
        ViewerMapViewModel(
            localRepository: dependencies.localSessionRepository,
            syncService: dependencies.sessionService,
            locationManager: dependencies.locationManager,
            accountName: user.displayName,
            coordinator: self
        )
    }

    private func makePhotographerMapViewModel() -> PhotographerMapViewModel {
        PhotographerMapViewModel(
            photographerId: user.id,
            locationManager: dependencies.locationManager,
            sessionRepository: dependencies.remoteSessionRepository,
            accountName: user.displayName,
            coordinator: self
        )
    }

    private func makeSessionDetailViewModel(sessionId: String) -> SessionDetailViewModel {
        SessionDetailViewModel(
            sessionId: sessionId,
            localRepository: dependencies.localSessionRepository,
            remoteRepository: dependencies.remoteSessionRepository,
            sessionWriter: dependencies.remoteSessionRepository,
            // Drives the ownership check — only the author sees status controls.
            currentUserId: user.id,
            coordinator: self
        )
    }

    /// `coordinate` seeds the form with the pin chosen on the map. Passing `nil`
    /// opens an empty composer, which the ViewModel refuses to publish.
    private func makeCreateSessionViewModel(coordinate: Coordinate?) -> CreateSessionViewModel {
        CreateSessionViewModel(
            selectedCoordinate: coordinate,
            sessionRepository: dependencies.remoteSessionRepository,
            authRepository: dependencies.authRepository,
            coordinator: self
        )
    }
}

// MARK: - My sessions

/// A photographer's own sessions as a list. Reuses `PhotographerMapViewModel`,
/// which already loads exactly this data, rather than duplicating the query.
struct MySessionsView: View {

    @State private var viewModel: PhotographerMapViewModel

    init(viewModel: PhotographerMapViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        List {
            if viewModel.mySessions.isEmpty && !viewModel.isLoadingSessions {
                ContentUnavailableView(
                    "No sessions yet",
                    systemImage: "camera",
                    description: Text("Pin a spot on the map to publish your first session.")
                )
            }

            ForEach(viewModel.mySessions) { session in
                Button {
                    viewModel.showSessionDetail(for: session)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.date, format: .dateTime.weekday().day().month())
                            .font(.headline)
                        Text("\(session.startTime.formatted(date: .omitted, time: .shortened)) – \(session.endTime.formatted(date: .omitted, time: .shortened))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(session.status.rawValue.capitalized)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle("My Sessions")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if viewModel.isLoadingSessions { ProgressView() }
        }
        .task { await viewModel.loadMySessions() }
        .refreshable { await viewModel.loadMySessions() }
    }
}
