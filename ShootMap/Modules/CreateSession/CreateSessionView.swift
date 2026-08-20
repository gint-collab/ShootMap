//
//  CreateSessionView.swift
//  ShootMap
//
//  Created by Septuagint Murito on 8/19/26.
//

import SwiftUI

/// Form for composing and publishing a new photo session.
///
/// Presentation only: it binds to the ViewModel, renders what the ViewModel
/// derives, and forwards intent. No validation rules, no persistence, no
/// Firebase, no SwiftData, and no navigation — `Publish` and `Cancel` both go
/// through the ViewModel to `MainCoordinator`.
struct CreateSessionView: View {

    @State private var viewModel: CreateSessionViewModel

    init(viewModel: CreateSessionViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Form {
                    locationSection
                    scheduleSection
                    if let message = viewModel.errorMessage {
                        errorSection(message)
                    }
                }
                .navigationTitle("New Session")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .disabled(viewModel.isSaving)
                .interactiveDismissDisabled(viewModel.isSaving)
                
                publishSection
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
            }
        }
    }

    // MARK: - Location

    private var locationSection: some View {
        Section("Location") {
            if let coordinate = viewModel.selectedCoordinate {
                LabeledContent("Selected") {
                    Text(coordinate.formatted)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            } else {
                Label(
                    "No location chosen. Go back to the map and tap your spot.",
                    systemImage: "mappin.slash"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Schedule

    private var scheduleSection: some View {
        Section("Schedule") {
            DatePicker(
                "Date",
                selection: $viewModel.date,
                displayedComponents: .date
            )

            DatePicker(
                "Start Time",
                selection: $viewModel.startTime,
                displayedComponents: .hourAndMinute
            )
            .onChange(of: viewModel.startTime) { _, _ in
                viewModel.startTimeDidChange()
            }

            DatePicker(
                "End Time",
                selection: $viewModel.endTime,
                displayedComponents: .hourAndMinute
            )
            .onChange(of: viewModel.endTime) { _, _ in
                viewModel.endTimeDidChange()
            }

            LabeledContent("Duration") {
                Text(durationText)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Formatting only — the ViewModel supplies the raw interval.
    private var durationText: String {
        let minutes = max(0, Int(viewModel.duration) / 60)
        return Duration.seconds(minutes * 60)
            .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    // MARK: - Errors

    private func errorSection(_ message: String) -> some View {
        Section {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text(message)
                    .font(.footnote)
                Spacer(minLength: 0)
                Button {
                    viewModel.dismissError()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(.red)
        }
    }

    // MARK: - Publish

    private var publishSection: some View {
        VStack(spacing: 32) {
            Button {
                Task { await viewModel.save() }
            } label: {
                HStack {
                    Spacer()
                    if viewModel.isSaving {
                        ProgressView()
                    } else {
                        Text("Publish Session").fontWeight(.semibold)
                    }
                    Spacer()
                }
            }
            // `canSave` already accounts for `isSaving`, so a double tap cannot
            // start two publishes.
            .disabled(!viewModel.canSave)
            .frame(maxWidth: .infinity)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            
            // Always explains a disabled button, rather than leaving the user
            // tapping a control that silently does nothing.
            if let reason = viewModel.validationMessage {
                Text(reason)
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel", role: .cancel) {
                viewModel.cancel()
            }
            .disabled(viewModel.isSaving)
        }
    }
}

// MARK: - Formatting

private extension Coordinate {
    /// Display-only rendering of a domain value.
    var formatted: String {
        String(format: "%.4f, %.4f", latitude, longitude)
    }
}
