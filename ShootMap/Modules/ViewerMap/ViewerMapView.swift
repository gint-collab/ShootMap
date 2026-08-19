//
//  ViewerMapView.swift
//  ShootMap
//
//  Created by Septuagint Murito on 8/19/26.
//

import SwiftUI
import MapKit

/// The viewer's map: browse upcoming photo sessions and open a photographer's
/// details.
///
/// Talks only to `ViewerMapViewModel`. No Firebase, no SwiftData, no repository
/// access, no filtering logic, and no navigation — tapping a pin reports intent
/// to the ViewModel, which delegates to `MainCoordinator`.
struct ViewerMapView: View {

    @State private var viewModel: ViewerMapViewModel

    /// MapKit-specific view state; it has no meaning in the ViewModel.
    @State private var cameraPosition: MapCameraPosition = .automatic

    /// The pin whose callout is open.
    @State private var selectedSessionId: String?

    /// Confirmation is view state — the ViewModel only hears the decision.
    @State private var isConfirmingSignOut = false

    @Environment(\.openURL) private var openURL

    init(viewModel: ViewerMapViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        map
            .safeAreaInset(edge: .top) { filterBar }
            .safeAreaInset(edge: .bottom) { bottomBar }
            .overlay(alignment: .center) { initialLoadOverlay }
            .navigationTitle("Sessions Nearby")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .confirmationDialog(
                "Sign out of ShootMap?",
                isPresented: $isConfirmingSignOut,
                titleVisibility: .visible
            ) {
                Button("Sign Out", role: .destructive) { viewModel.signOut() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Saved sessions on this device will be cleared.")
            }
            .task { await viewModel.start() }
            .onChange(of: viewModel.userLocation) { _, location in
                // Centre once the first fix arrives; panning afterwards is the
                // user's, so the ViewModel stops seeding the region.
                guard let location else { return }
                withAnimation {
                    cameraPosition = .region(
                        MKCoordinateRegion(
                            center: location.clCoordinate,
                            latitudinalMeters: 5_000,
                            longitudinalMeters: 5_000
                        )
                    )
                }
            }
            .onDisappear { viewModel.stop() }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                // Viewers get no authoring actions — the menu mirrors exactly
                // what the role is permitted to do.
                Section("Viewer · \(viewModel.accountName)") {
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        Task { await viewModel.refresh() }
                    }
                }

                Button("Sign Out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    isConfirmingSignOut = true
                }
            } label: {
                Image(systemName: "person.crop.circle")
            }
        }
    }

    // MARK: - Map

    private var map: some View {
        Map(position: $cameraPosition, selection: $selectedSessionId) {
            // Only drawn once authorization is granted.
            if viewModel.isLocationAvailable {
                UserAnnotation()
            }

            ForEach(viewModel.sessions) { session in
                Annotation(
                    session.photographerName,
                    coordinate: session.coordinate.clCoordinate
                ) {
                    SessionPin(
                        session: session,
                        isSelected: selectedSessionId == session.id
                    )
                    .onTapGesture {
                        selectedSessionId = session.id
                    }
                }
                .tag(session.id)
            }
        }
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            Task { await viewModel.regionDidChange(to: context.region.domainRegion) }
        }
        .ignoresSafeArea(edges: .top)
    }

    // MARK: - Filters

    private var filterBar: some View {
        VStack(spacing: 8) {
            if viewModel.isLocationDenied {
                locationDeniedNotice
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(SessionDateFilter.allCases) { filter in
                        FilterChip(
                            title: filter.title,
                            isSelected: viewModel.dateFilter == filter
                        ) {
                            Task { await viewModel.selectFilter(filter) }
                        }
                    }
                }
                .padding(.horizontal)
            }

            syncStatusBar
        }
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Location permission

    /// Browsing still works without location, so this is an informational notice
    /// with a route to Settings — never a blocking wall.
    private var locationDeniedNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "location.slash")
            Text("Location is off. Pan the map to explore an area.")
                .font(.caption)
            Spacer(minLength: 0)
            if let settings = URL(string: UIApplication.openSettingsURLString) {
                Button("Settings") { openURL(settings) }
                    .font(.caption.weight(.semibold))
            }
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal)
    }

    // MARK: - Sync status

    @ViewBuilder
    private var syncStatusBar: some View {
        switch viewModel.loadState {
        case .idle, .loadingInitial:
            EmptyView()

        case .live:
            statusLabel("Up to date", systemImage: "checkmark.circle.fill", tint: .green)

        case let .showingCache(syncedAt):
            statusLabel(
                syncedAt.map { "Updating… last synced \($0.formatted(.relative(presentation: .named)))" }
                    ?? "Updating…",
                systemImage: "arrow.triangle.2.circlepath",
                tint: .secondary
            )

        case let .offline(syncedAt, message):
            statusLabel(
                syncedAt.map { "Offline · saved sessions from \($0.formatted(.relative(presentation: .named)))" }
                    ?? message,
                systemImage: "wifi.slash",
                tint: .orange
            )
        }
    }

    private func statusLabel(
        _ text: String,
        systemImage: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(text).lineLimit(1)
        }
        .font(.caption)
        .foregroundStyle(tint)
        .padding(.horizontal)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Bottom detail card

    @ViewBuilder
    private var bottomBar: some View {
        if let session = selectedSession {
            SessionCallout(session: session) {
                viewModel.showSessionDetail(for: session)
            } onClose: {
                selectedSessionId = nil
            }
            .padding()
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if viewModel.isEmpty {
            Text("No sessions \(viewModel.dateFilter.title.lowercased()) in this area.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding()
                .frame(maxWidth: .infinity)
                .background(.bar)
        }
    }

    private var selectedSession: PhotoSession? {
        guard let selectedSessionId else { return nil }
        return viewModel.sessions.first { $0.id == selectedSessionId }
    }

    // MARK: - Loading

    @ViewBuilder
    private var initialLoadOverlay: some View {
        if viewModel.isLoading {
            ProgressView("Loading sessions…")
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - Pin

private struct SessionPin: View {
    let session: PhotoSession
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: "camera.fill")
                .font(.caption)
                .foregroundStyle(.white)
                .padding(isSelected ? 10 : 7)
                .background(Circle().fill(tint))
                .shadow(radius: 2)

            Text(session.photographerName)
                .font(.caption2)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(.regularMaterial, in: Capsule())
        }
        .scaleEffect(isSelected ? 1.1 : 1)
        .animation(.snappy, value: isSelected)
    }

    private var tint: Color {
        session.status == .ongoing ? .green : .blue
    }
}

// MARK: - Callout

private struct SessionCallout: View {
    let session: PhotoSession
    let onOpen: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.photographerName)
                        .font(.headline)

                    if let page = session.facebookPageName {
                        Label(page, systemImage: "link")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)

                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Label {
                Text(session.date, format: .dateTime.weekday(.wide).day().month(.wide))
            } icon: {
                Image(systemName: "calendar")
            }
            .font(.subheadline)

            Label {
                Text("\(session.startTime.formatted(date: .omitted, time: .shortened)) – \(session.endTime.formatted(date: .omitted, time: .shortened))")
            } icon: {
                Image(systemName: "clock")
            }
            .font(.subheadline)

            Button(action: onOpen) {
                Text("View Details")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 6)
    }
}

// MARK: - Filter chip

private struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.15))
                )
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - MapKit bridging
//
// Confined to the view layer so the domain stays free of MapKit.

private extension Coordinate {
    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

private extension MKCoordinateRegion {
    var domainRegion: CoordinateRegion {
        CoordinateRegion(
            center: (try? Coordinate(
                latitude: center.latitude,
                longitude: center.longitude
            )) ?? .zero,
            latitudeDelta: span.latitudeDelta,
            longitudeDelta: span.longitudeDelta
        )
    }
}
