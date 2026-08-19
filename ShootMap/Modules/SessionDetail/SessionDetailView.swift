//
//  SessionDetailView.swift
//  ShootMap
//
//  Created by Septuagint Murito on 8/19/26.
//

import SwiftUI
import MapKit

/// Details for a single photo session: who is shooting, where, and when.
///
/// Presentation only — it receives the `PhotoSession` from
/// `SessionDetailViewModel` and renders it. No Firebase, no SwiftData, no
/// repository access, and no navigation logic.
struct SessionDetailView: View {

    @State private var viewModel: SessionDetailViewModel

    @Environment(\.openURL) private var openURL

    init(viewModel: SessionDetailViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        Group {
            if let session = viewModel.session {
                content(for: session)
            } else if viewModel.isLoading {
                ProgressView("Loading session…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                unavailable
            }
        }
        .navigationTitle("Session")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .refreshable { await viewModel.refresh() }
    }

    // MARK: - Content

    private func content(for session: PhotoSession) -> some View {
        List {
            if let message = viewModel.errorMessage {
                errorSection(message)
            }

            photographerSection(session)
            scheduleSection(session)
            locationSection(session)
        }
        .listStyle(.insetGrouped)
    }

    // MARK: Photographer

    private func photographerSection(_ session: PhotoSession) -> some View {
        Section("Photographer") {
            LabeledContent("Name", value: session.photographerName)

            if viewModel.hasFacebookPage {
                if let title = viewModel.facebookPageTitle {
                    LabeledContent("Facebook Page", value: title)
                }

                if let url = viewModel.facebookPageURL {
                    Button {
                        openURL(url)
                    } label: {
                        Label("Open Facebook Page", systemImage: "arrow.up.right.square")
                    }
                }
            } else {
                Text("No Facebook page provided.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Schedule

    private func scheduleSection(_ session: PhotoSession) -> some View {
        Section("Schedule") {
            LabeledContent("Status") {
                StatusBadge(status: session.status)
            }

            LabeledContent("Date") {
                Text(session.date, format: .dateTime.weekday(.wide).day().month(.wide).year())
            }

            LabeledContent("Start Time") {
                Text(session.startTime, format: .dateTime.hour().minute())
            }

            LabeledContent("End Time") {
                Text(session.endTime, format: .dateTime.hour().minute())
            }
        }
    }

    // MARK: Location

    private func locationSection(_ session: PhotoSession) -> some View {
        Section("Location") {
            Map(initialPosition: .region(session.coordinate.region())) {
                Marker(session.photographerName, coordinate: session.coordinate.clCoordinate)
            }
            .frame(height: 180)
            .listRowInsets(EdgeInsets())
            .allowsHitTesting(false)

            LabeledContent("Coordinates") {
                Text(session.coordinate.formatted)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Button {
                openInAppleMaps(session)
            } label: {
                Label("Open in Apple Maps", systemImage: "map")
            }
        }
    }

    // MARK: - Errors / empty

    private func errorSection(_ message: String) -> some View {
        Section {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text(message).font(.footnote)
                Spacer(minLength: 0)
                Button {
                    viewModel.dismissError()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(.orange)
        }
    }

    private var unavailable: some View {
        ContentUnavailableView {
            Label("Session Unavailable", systemImage: "camera.metering.unknown")
        } description: {
            Text(viewModel.errorMessage ?? "This session is no longer available.")
        } actions: {
            Button("Go Back") { viewModel.goBack() }
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Apple Maps

    /// Hands the pin to Apple Maps. `MKMapItem` is a presentation concern, so it
    /// never appears in the ViewModel.
    private func openInAppleMaps(_ session: PhotoSession) {
        let placemark = MKPlacemark(coordinate: session.coordinate.clCoordinate)
        let item = MKMapItem(placemark: placemark)
        item.name = "\(session.photographerName) · Photo Session"
        item.openInMaps(launchOptions: [
            MKLaunchOptionsMapCenterKey: NSValue(mkCoordinate: session.coordinate.clCoordinate)
        ])
    }
}

// MARK: - Status badge

private struct StatusBadge: View {
    let status: SessionStatus

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(tint.opacity(0.15)))
            .foregroundStyle(tint)
    }

    /// Display strings only — the meaning of each case lives in the domain.
    private var title: String {
        switch status {
        case .scheduled: "Scheduled"
        case .ongoing: "Happening now"
        case .completed: "Completed"
        case .cancelled: "Cancelled"
        }
    }

    private var tint: Color {
        switch status {
        case .scheduled: .blue
        case .ongoing: .green
        case .completed: .secondary
        case .cancelled: .red
        }
    }
}

// MARK: - MapKit bridging
//
// Confined to the view layer so the domain stays free of MapKit.

private extension Coordinate {
    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    func region(metres: CLLocationDistance = 1_000) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: clCoordinate,
            latitudinalMeters: metres,
            longitudinalMeters: metres
        )
    }

    var formatted: String {
        String(format: "%.5f, %.5f", latitude, longitude)
    }
}
