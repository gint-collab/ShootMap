//
//  PhotographerMapView.swift
//  ShootMap
//
//  Created by Septuagint Murito on 8/19/26.
//

import SwiftUI
import MapKit

/// The photographer's map: drop a pin where you'll be shooting, see your
/// existing sessions, and start composing a new one.
///
/// Presentation only. It renders what the ViewModel exposes and forwards user
/// intent back to it — no validation, no persistence, no Firebase, no SwiftData,
/// and no navigation path manipulation.
struct PhotographerMapView: View {

    @State private var viewModel: PhotographerMapViewModel

    /// Camera state is pure view state — it has no meaning outside MapKit, so it
    /// stays here rather than leaking `MapCameraPosition` into the ViewModel.
    @State private var cameraPosition: MapCameraPosition = .automatic

    init(viewModel: PhotographerMapViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        map
            .overlay(alignment: .top) { errorBanner }
            .safeAreaInset(edge: .bottom) { bottomBar }
            .navigationTitle("Your Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .task { await viewModel.onAppear() }
            .onChange(of: viewModel.userLocation) { _, location in
                guard let location else { return }
                withAnimation { cameraPosition = .region(location.region()) }
            }
    }

    // MARK: - Map

    private var map: some View {
        // `MapReader` converts a tap in view space into a coordinate. This is the
        // only place raw latitude/longitude appears, and it is handed straight to
        // the ViewModel, which validates it before it becomes state.
        MapReader { proxy in
            Map(position: $cameraPosition) {
                if viewModel.isLocationAvailable {
                    UserAnnotation()
                }

                // Existing sessions.
                ForEach(viewModel.mySessions) { session in
                    Annotation(
                        session.photographerName,
                        coordinate: session.coordinate.clCoordinate
                    ) {
                        SessionMarker(status: session.status)
                            .onTapGesture { viewModel.showSessionDetail(for: session) }
                    }
                }

                // The pin being placed.
                if let selected = viewModel.selectedCoordinate {
                    Annotation("New session", coordinate: selected.clCoordinate) {
                        SelectedPin()
                    }
                }
            }
            .mapControls {
                MapUserLocationButton()
                MapCompass()
            }
            .onTapGesture { point in
                guard let coordinate = proxy.convert(point, from: .local) else { return }
                viewModel.selectCoordinate(
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude
                )
            }
        }
        .ignoresSafeArea(edges: .top)
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 12) {
            if viewModel.isLocationDenied {
                locationDeniedNotice
            }

            Text(viewModel.hasSelection
                 ? "Pin placed. Ready to publish your session."
                 : "Tap anywhere on the map to choose your shooting spot.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            HStack(spacing: 12) {
                if viewModel.hasSelection {
                    Button("Clear", role: .cancel) {
                        viewModel.clearSelection()
                    }
                    .buttonStyle(.bordered)
                }

                Button {
                    viewModel.createSessionAtSelectedLocation()
                } label: {
                    Text("Create Photo Session")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canCreateSession)
            }
        }
        .padding()
        .background(.bar)
    }

    private var locationDeniedNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "location.slash")
            Text("Location is off. You can still pick a spot by tapping the map.")
                .font(.footnote)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.secondary)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button("My Sessions", systemImage: "list.bullet") {
                viewModel.showMySessions()
            }
        }

        ToolbarItem(placement: .topBarLeading) {
            if viewModel.isLoadingSessions {
                ProgressView()
            }
        }
    }

    // MARK: - Error banner

    @ViewBuilder
    private var errorBanner: some View {
        if let message = viewModel.errorMessage {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text(message).font(.subheadline)
                Spacer(minLength: 0)
                Button {
                    viewModel.dismissError()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(.red)
            .padding()
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

// MARK: - Pins

private struct SelectedPin: View {
    var body: some View {
        Image(systemName: "camera.viewfinder")
            .font(.title2)
            .foregroundStyle(.white)
            .padding(8)
            .background(Circle().fill(.blue))
            .shadow(radius: 3)
    }
}

private struct SessionMarker: View {
    let status: SessionStatus

    var body: some View {
        Image(systemName: "camera.fill")
            .font(.caption)
            .foregroundStyle(.white)
            .padding(6)
            .background(Circle().fill(tint))
            .shadow(radius: 2)
    }

    /// Presentation-only mapping. The rule for *what* each status means lives in
    /// the domain; this only chooses a colour for it.
    private var tint: Color {
        switch status {
        case .scheduled: .orange
        case .ongoing: .green
        case .completed: .gray
        case .cancelled: .red
        }
    }
}

// MARK: - MapKit bridging
//
// Confined to the view layer so the domain's `Coordinate` never imports MapKit.

private extension Coordinate {
    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    func region(metres: CLLocationDistance = 2_000) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: clCoordinate,
            latitudinalMeters: metres,
            longitudinalMeters: metres
        )
    }
}
