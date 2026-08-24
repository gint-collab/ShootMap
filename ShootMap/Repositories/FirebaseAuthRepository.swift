//
//  FirebaseAuthRepository.swift
//  ShootMap
//
//  Created by Septuagint Murito on 8/17/26.
//

import Foundation
// `@preconcurrency`: Firebase's `Auth` and `Firestore` are thread-safe but not
// yet annotated `Sendable`. Without this, storing them in a `Sendable` type is
// a warning today and an error under the Swift 6 language mode.
@preconcurrency import FirebaseAuth
@preconcurrency import FirebaseFirestore

/// Firebase-backed implementation of `AuthRepositoryProtocol`.
///
/// Credentials live in FirebaseAuth; the profile (display name, role, Facebook
/// page) lives in the `users` Firestore collection. This type is the only place
/// that knows those are two separate stores.
///
/// Nothing Firebase-specific escapes: every method returns domain `User` values
/// and throws `AuthError`. `Auth` and `Firestore` are injected rather than
/// reached for statically, so an emulator-backed instance can be substituted
/// wholesale in integration tests.
nonisolated final class FirebaseAuthRepository: AuthRepositoryProtocol {

    private let auth: Auth
    private let firestore: Firestore

    init(auth: Auth, firestore: Firestore) {
        self.auth = auth
        self.firestore = firestore
    }

    private var users: CollectionReference {
        firestore.collection(FirestoreCollection.users)
    }

    // MARK: - Current user

    /// The signed-in user, or `nil` when signed out.
    ///
    /// Returns `nil` rather than throwing: callers asking "who is signed in?"
    /// treat "nobody" and "profile unreadable" identically — both mean there is
    /// no usable session.
    func currentUser() async -> User? {
        guard let uid = auth.currentUser?.uid else { return nil }
        return try? await profile(uid: uid)
    }

    // MARK: - Authentication state observation

    /// Emits on every authentication state change.
    ///
    /// FirebaseAuth's listener is synchronous while resolving the profile is
    /// asynchronous, so each change spawns a task that yields once the profile
    /// has been loaded. A user whose profile cannot be read is reported as
    /// `nil`, keeping "signed in" and "usable session" the same thing.
    var authStateUpdates: AsyncStream<User?> {
        AsyncStream { continuation in
            let handle = auth.addStateDidChangeListener { [weak self] _, firebaseUser in
                guard let self else {
                    continuation.finish()
                    return
                }
                guard let uid = firebaseUser?.uid else {
                    continuation.yield(nil)
                    return
                }
                Task {
                    continuation.yield(try? await self.profile(uid: uid))
                }
            }
            // Detaching on termination is what makes cancelling the consuming
            // task actually remove the listener rather than leak it.
            continuation.onTermination = { [auth] _ in
                auth.removeStateDidChangeListener(handle)
            }
        }
    }

    // MARK: - Sign up

    /// Creates the credential, then the profile document.
    ///
    /// If the profile step fails the new auth account is rolled back. Without
    /// that, the account would exist with no profile and every subsequent sign
    /// in would fail with `.profileMissing` — an unrecoverable state for the
    /// user, since the email would also be permanently taken.
    @discardableResult
    func signUp(with request: SignUpRequest) async throws -> User {
        let result = try await mapErrors {
            try await auth.createUser(withEmail: request.email, password: request.password)
        }

        let user = User(
            id: result.user.uid,
            email: request.email,
            displayName: request.displayName,
            facebookPageName: request.facebookPageName,
            facebookPageURL: request.facebookPageURL,
            role: request.role,
            createdAt: .now
        )

        do {
            // Domain rules are enforced before anything is persisted — e.g. a
            // photographer must have a Facebook page.
            try user.validate()
            // Wrapped so a Firestore rejection (most commonly undeployed
            // security rules) surfaces as a typed `AuthError` rather than a raw
            // NSError that the UI can only report as "something went wrong".
            try await mapErrors {
                try await users.document(user.id).setData(user.firestoreData)
            }
        } catch {
            try? await result.user.delete()
            throw error
        }
        return user
    }

    // MARK: - Login

    @discardableResult
    func signIn(with credentials: SignInCredentials) async throws -> User {
        let result = try await mapErrors {
            try await auth.signIn(withEmail: credentials.email, password: credentials.password)
        }
        return try await profile(uid: result.user.uid)
    }

    /// Naming alias for call sites that prefer "login".
    @discardableResult
    func login(with credentials: SignInCredentials) async throws -> User {
        try await signIn(with: credentials)
    }

    // MARK: - Logout

    func signOut() async throws {
        do {
            try auth.signOut()
        } catch {
            throw AuthError(error)
        }
    }

    /// Naming alias for call sites that prefer "logout".
    func logout() async throws {
        try await signOut()
    }

    // MARK: - Account management

    func sendPasswordReset(toEmail email: String) async throws {
        try await mapErrors {
            try await auth.sendPasswordReset(withEmail: email)
        }
    }

    func deleteAccount() async throws {
        guard let current = auth.currentUser else {
            throw AuthError.notAuthenticated
        }
        // Profile first: if account deletion then fails, the credential still
        // exists so the user can retry. An orphaned profile has no owner left
        // to clean it up.
        try await mapErrors {
            try await users.document(current.uid).delete()
            try await current.delete()
        }
    }

    // MARK: - Helpers

    /// Loads the Firestore profile that backs a Firebase credential.
    private func profile(uid: String) async throws -> User {
        let document = try await mapErrors {
            try await users.document(uid).getDocument()
        }
        guard let data = document.data() else {
            throw AuthError.profileMissing
        }
        return User(id: uid, data: data)
    }

    /// Runs `operation`, translating any provider error into an `AuthError`.
    private func mapErrors<T>(
        _ operation: () async throws -> T
    ) async throws -> T {
        do {
            return try await operation()
        } catch let error as AuthError {
            throw error
        } catch {
            throw AuthError(error)
        }
    }
}

// MARK: - Firebase error translation

private extension AuthError {

    /// Maps a FirebaseAuth / Firestore error onto the application's error model.
    ///
    /// Confined to this file so `AuthErrorCode` never appears anywhere else.
    init(_ error: Error) {
        let nsError = error as NSError

        // Firestore reports offline and rule rejections separately from FirebaseAuth.
        if nsError.domain == FirestoreErrorDomain {
            switch nsError.code {
            case FirestoreErrorCode.unavailable.rawValue,
                 FirestoreErrorCode.deadlineExceeded.rawValue:
                self = .networkUnavailable
                return
            case FirestoreErrorCode.permissionDenied.rawValue:
                self = .permissionDenied
                return
            case FirestoreErrorCode.unauthenticated.rawValue:
                self = .notAuthenticated
                return
            default:
                break
            }
        }

        guard let code = AuthErrorCode(rawValue: nsError.code),
              nsError.domain == AuthErrorDomain else {
            self = .unknown(message: nsError.localizedDescription)
            return
        }

        switch code {
        case .invalidEmail, .missingEmail:
            self = .invalidEmail
        case .emailAlreadyInUse, .accountExistsWithDifferentCredential, .credentialAlreadyInUse:
            self = .emailAlreadyInUse
        case .weakPassword:
            self = .weakPassword

        // Merged so the API cannot be used to discover which emails are registered.
        case .wrongPassword, .userNotFound, .invalidCredential:
            self = .invalidCredentials

        case .userDisabled:
            self = .accountDisabled
        case .requiresRecentLogin:
            self = .requiresRecentLogin
        case .networkError:
            self = .networkUnavailable
        case .tooManyRequests:
            self = .tooManyRequests
        case .operationNotAllowed:
            self = .operationNotAllowed
        case .nullUser, .userTokenExpired, .invalidUserToken:
            self = .notAuthenticated
        default:
            self = .unknown(message: nsError.localizedDescription)
        }
    }
}
