//
//  SignUpView.swift
//  ShootMap
//
//  Created by Septuagint Murito on 8/20/26.
//

import SwiftUI

/// Account creation. Presentation only — validation and registration live in
/// `SignUpViewModel`, navigation in `AuthCoordinator`.
struct SignUpView: View {

    @State private var viewModel: SignUpViewModel

    init(viewModel: SignUpViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        VStack( spacing: 32) {
            Form {
                accountTypeSection
                detailsSection

                // Shown only for photographers, because only that role requires it.
                if viewModel.requiresFacebookPage {
                    facebookSection
                }

                if let message = viewModel.errorMessage {
                    errorSection(message)
                }
            }
            .navigationTitle("Create Account")
            .navigationBarTitleDisplayMode(.inline)
            .disabled(viewModel.isRegistering)
            
            submitSection
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
        }
    }

    // MARK: - Sections

    private var accountTypeSection: some View {
        Section("I am a…") {
            Picker("Account type", selection: $viewModel.accountType) {
                ForEach(SignUpViewModel.AccountType.allCases) { type in
                    Text(type.title).tag(type)
                }
            }
            .pickerStyle(.segmented)

            Text(viewModel.accountType.explanation)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var detailsSection: some View {
        Section {
            TextField("Display name", text: $viewModel.displayName)
                .textContentType(.name)

            TextField("Email", text: $viewModel.email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            SecureField("Password", text: $viewModel.password)
                .textContentType(.newPassword)
        } header: {
            Text("Your details")
        } footer: {
            Text("Passwords must be at least \(SignUpViewModel.minimumPasswordLength) characters.")
        }
    }

    private var facebookSection: some View {
        Section {
            TextField("Page name", text: $viewModel.facebookPageName)
                .textInputAutocapitalization(.words)

            TextField("Page link (optional)", text: $viewModel.facebookPageURL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } header: {
            Text("Facebook page")
        } footer: {
            Text("Viewers use this to find your work, so photographers need at least one.")
        }
    }

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
            .foregroundStyle(.red)
        }
    }

    private var submitSection: some View {
        VStack(spacing: 24) {
            Button {
                Task { await viewModel.signUp() }
            } label: {
                HStack {
                    Spacer()
                    if viewModel.isRegistering {
                        ProgressView()
                    } else {
                        Text("Create Account").fontWeight(.semibold)
                    }
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 24)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!viewModel.canSubmit)
            
            Button("I already have an account") {
                viewModel.showLogin()
            }
            .font(.footnote)
        }
    }
}
