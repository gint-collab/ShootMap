//
//  FirebaseManager.swift
//  ShootMap
//
//  Created by Septuagint Murito on 8/15/26.
//

import Foundation
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore

// MARK: - Configuration errors

/// Failures raised while bringing Firebase up.
///
/// These replace Firebase's own `fatalError`-on-misconfiguration behaviour with
/// a typed error the app layer can surface or log.
nonisolated enum FirebaseConfigurationError: Error, Equatable, Sendable {
    /// No `GoogleService-Info.plist` was found in the given bundle.
    case missingConfigurationFile(resourceName: String)
    /// The plist exists but could not be parsed into `FirebaseOptions`.
    case invalidConfigurationFile(path: String)
}

extension FirebaseConfigurationError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case let .missingConfigurationFile(name):
            return "Missing \(name).plist. Download it from the Firebase console and add it to the app target."
        case let .invalidConfigurationFile(path):
            return "Could not read Firebase options from \(path)."
        }
    }
}

// MARK: - Injection seam

/// Supplies configured Firebase clients to the data layer.
///
/// Only infrastructure types (`FirestorePhotoSessionRepository`,
/// `FirebaseAuthRepository`, …) may depend on this. ViewModels and coordinators
/// depend on `AuthRepositoryProtocol` / `PhotoSessionRepositoryProtocol`
/// instead, so `FirebaseAuth` and `FirebaseFirestore` never reach the
/// presentation layer.
nonisolated protocol FirebaseProviding: Sendable {
    /// The configured authentication client.
    var auth: Auth { get }
    /// The configured Firestore client.
    var firestore: Firestore { get }
}

// MARK: - Centralised Firestore schema

/// Single source of truth for collection names, so no string literal is
/// duplicated across repositories.
nonisolated enum FirestoreCollection {
    static let users = "users"
    static let photoSessions = "photoSessions"
}

// MARK: - Emulator settings

/// Points the SDK at local emulators. Inject in UI tests and integration tests
/// to keep them off production data.
nonisolated struct FirebaseEmulatorSettings: Equatable, Sendable {
    let host: String
    let authPort: Int
    let firestorePort: Int

    init(host: String = "127.0.0.1", authPort: Int = 9099, firestorePort: Int = 8080) {
        self.host = host
        self.authPort = authPort
        self.firestorePort = firestorePort
    }

    /// Reads `-firebaseUseEmulator` from the launch arguments, so tests can opt
    /// in without the app hardcoding a test-only branch.
    static func fromLaunchEnvironment() -> FirebaseEmulatorSettings? {
        UserDefaults.standard.bool(forKey: "firebaseUseEmulator") ? FirebaseEmulatorSettings() : nil
    }
}

// MARK: - Manager

/// Owns Firebase start-up and vends the shared clients.
///
/// Responsibilities are deliberately narrow: configure the SDK exactly once and
/// hand back `Auth` / `Firestore`. It performs no queries, holds no domain
/// knowledge, and maps no models.
nonisolated final class FirebaseManager: FirebaseProviding, @unchecked Sendable {

    /// Shared instance for the composition root. Prefer injecting
    /// `any FirebaseProviding`; this exists so `ShootMapApp` has one call site.
    static let shared = FirebaseManager()

    private let lock = NSLock()
    private var app: FirebaseApp?
    private var cachedAuth: Auth?
    private var cachedFirestore: Firestore?
    private let emulator: FirebaseEmulatorSettings?

    /// - Parameter emulator: when non-nil, both clients are redirected to local
    ///   emulators on first access.
    init(emulator: FirebaseEmulatorSettings? = nil) {
        self.emulator = emulator
    }

    // MARK: Configuration

    /// Configures Firebase from a `GoogleService-Info.plist` in `bundle`.
    ///
    /// Idempotent: repeated calls are no-ops, so it is safe to call from both
    /// the app entry point and a test harness.
    ///
    /// - Throws: `FirebaseConfigurationError` if the plist is absent or unreadable.
    func configure(
        bundle: Bundle = .main,
        resourceName: String = "GoogleService-Info"
    ) throws {
        lock.lock()
        defer { lock.unlock() }

        guard app == nil else { return }

        // Another component (or a previous test) may already have configured it.
        if let existing = FirebaseApp.app() {
            app = existing
            return
        }

        guard let path = bundle.path(forResource: resourceName, ofType: "plist") else {
            throw FirebaseConfigurationError.missingConfigurationFile(resourceName: resourceName)
        }
        guard let options = FirebaseOptions(contentsOfFile: path) else {
            throw FirebaseConfigurationError.invalidConfigurationFile(path: path)
        }

        FirebaseApp.configure(options: options)

        guard let configured = FirebaseApp.app() else {
            throw FirebaseConfigurationError.invalidConfigurationFile(path: path)
        }
        app = configured
    }

    // MARK: FirebaseProviding

    var auth: Auth {
        lock.lock()
        defer { lock.unlock() }

        if let cachedAuth { return cachedAuth }

        let instance = app.map { Auth.auth(app: $0) } ?? Auth.auth()
        if let emulator {
            instance.useEmulator(withHost: emulator.host, port: emulator.authPort)
        }
        cachedAuth = instance
        return instance
    }

    var firestore: Firestore {
        lock.lock()
        defer { lock.unlock() }

        if let cachedFirestore { return cachedFirestore }

        let instance = app.map { Firestore.firestore(app: $0) } ?? Firestore.firestore()
        instance.settings = Self.makeSettings(emulator: emulator)
        cachedFirestore = instance
        return instance
    }

    // MARK: Settings

    /// Firestore's own on-disk cache is enabled via `PersistentCacheSettings`.
    ///
    /// It is intentionally *not* the app's cache of record: SwiftData is, because
    /// it supports the typed predicate queries the map needs. This is only an
    /// offline-write buffer for the SDK.
    private static func makeSettings(emulator: FirebaseEmulatorSettings?) -> FirestoreSettings {
        let settings = FirestoreSettings()
        // Modern replacement for the deprecated `isPersistenceEnabled` /
        // `cacheSizeBytes` pair.
        settings.cacheSettings = PersistentCacheSettings()

        if let emulator {
            settings.host = "\(emulator.host):\(emulator.firestorePort)"
            settings.isSSLEnabled = false
            // Emulators must not serve stale local data between test runs.
            settings.cacheSettings = MemoryCacheSettings()
        }
        return settings
    }
}
