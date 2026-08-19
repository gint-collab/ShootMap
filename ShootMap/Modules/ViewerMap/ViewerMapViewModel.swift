//
//  ViewerMapViewModel.swift
//  ShootMap
//
//  Created by Septuagint Murito on 8/19/26.
//

import Foundation
import Observation

/// Date windows the viewer can filter the map by.
///
/// Past-oriented by design: viewers browse sessions that have already happened
/// as well as ones still to come, so the windows look backwards from today.
///
/// Lives in the ViewModel layer, not the view: the view renders the cases and
/// reports selection, but the date arithmetic belongs here.
nonisolated enum SessionDateFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case today
    case yesterday
    case lastWeek

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .today: "Today"
        case .yesterday: "Yesterday"
        case .lastWeek: "Last Week"
        }
    }

    /// The window a session's start time must fall in, or `nil` for no bound at
    /// all.
    ///
    /// Windows are **not** floored at `now`: a shoot that finished earlier today
    /// still falls inside "Today". Status filtering decides relevance, not the
    /// clock.
    func dateRange(now: Date = .now, calendar: Calendar = .current) -> ClosedRange<Date>? {
        switch self {
        case .all:
            // No bound whatsoever — every scheduled session, past or future.
            return nil

        case .today:
            return calendar.dayRange(containing: now)

        case .yesterday:
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: now) else { return nil }
            return calendar.dayRange(containing: yesterday)

        case .lastWeek:
            // A rolling seven-day window ending today, rather than the previous
            // calendar week. "Last week" then always means "the past week from
            // now", so the window never collapses to a couple of days just
            // because today happens to be early in the calendar week.
            let today = calendar.dayRange(containing: now)
            guard let weekAgo = calendar.date(byAdding: .day, value: -6, to: now) else { return nil }
            return calendar.startOfDay(for: weekAgo)...today.upperBound
        }
    }
}

private extension Calendar {
    /// Midnight-to-midnight range for the day containing `date`. The upper bound
    /// is nudged back so a session starting exactly at midnight belongs to one
    /// day only, never both.
    func dayRange(containing date: Date) -> ClosedRange<Date> {
        let start = startOfDay(for: date)
        let end = self.date(byAdding: .day, value: 1, to: start) ?? date
        return start...end.addingTimeInterval(-0.001)
    }
}

/// Drives the viewer's map: browse upcoming sessions and open a photographer's
/// details.
///
/// Cache-first by design. The cache is displayed immediately, Firestore
/// reconciliation happens in the background, and the map is then re-read **from
/// the cache** so what the user sees always matches what is persisted.
///
/// Imports only `Foundation` and `Observation` — no MapKit, no Firebase, no
/// SwiftData, no `ModelContext`, no SwiftUI.
@MainActor
@Observable
final class ViewerMapViewModel {

    /// Where the currently displayed sessions came from, so the UI can label
    /// stale data rather than silently presenting it as live.
    enum LoadState: Equatable {
        case idle
        /// First load, nothing to show yet.
        case loadingInitial
        /// Showing cached data while the network is in flight.
        case showingCache(syncedAt: Date?)
        case live
        /// Remote failed, but cached data is still on screen.
        case offline(syncedAt: Date?, message: String)
    }

    // MARK: - State

    private(set) var sessions: [PhotoSession] = []
    private(set) var loadState: LoadState = .idle

    /// Non-fatal message shown alongside data, never instead of it.
    private(set) var errorMessage: String?

    /// The map viewport. Changing it re-runs the query for the new area.
    private(set) var region: CoordinateRegion?

    /// Active date window. Set via `selectFilter(_:)`.
    private(set) var dateFilter: SessionDateFilter = .all

    /// Current location authorization. Drives the permission prompt and the
    /// "location is off" notice.
    private(set) var authorization: LocationAuthorization = .notDetermined

    /// The viewer's own position, once resolved. `nil` means the map should
    /// keep whatever region it already has rather than jumping to (0, 0).
    private(set) var userLocation: Coordinate?

    // MARK: - Derived

    var isLoading: Bool { loadState == .loadingInitial }

    var isEmpty: Bool { sessions.isEmpty && !isLoading }

    /// True when the user is looking at cached data that could not be refreshed.
    var isShowingStaleData: Bool {
        if case .offline = loadState { return true }
        return false
    }

    /// Location was refused, so the view can offer a Settings prompt. Browsing
    /// still works — the viewer just has to pan the map themselves.
    var isLocationDenied: Bool { authorization.isDenied }

    /// Whether the map may draw the blue user-location dot. Asking MapKit to
    /// show it without authorization only produces a console warning.
    var isLocationAvailable: Bool { authorization.isAuthorized }

    /// When the displayed data was last reconciled with the server, if known.
    var lastSyncedAt: Date? {
        switch loadState {
        case let .showingCache(syncedAt), let .offline(syncedAt, _): syncedAt
        default: nil
        }
    }

    // MARK: - Dependencies

    /// Display name of the signed-in viewer, for the account menu.
    let accountName: String

    /// Read directly for the instant first paint, and re-read after each
    /// reconciliation so the map mirrors the persisted truth.
    private let localRepository: any LocalPhotoSessionRepositoryProtocol

    /// Owns Firestore↔cache reconciliation. The ViewModel never chooses between
    /// remote and local itself.
    private let syncService: any PhotoSessionSyncServiceProtocol

    /// Location is optional for browsing: a viewer who refuses permission can
    /// still pan the map, so nothing here treats denial as an error.
    private let locationManager: any LocationManagerProtocol

    /// `weak` because the coordinator owns this ViewModel.
    private weak var coordinator: (any MainCoordinatorProtocol)?

    /// The live sync subscription, cancelled on teardown and whenever the query
    /// changes, so panning cannot leave orphaned listeners running.
    private var syncTask: Task<Void, Never>?

    // MARK: - Init

    init(
        localRepository: any LocalPhotoSessionRepositoryProtocol,
        syncService: any PhotoSessionSyncServiceProtocol,
        locationManager: any LocationManagerProtocol,
        accountName: String = "",
        coordinator: (any MainCoordinatorProtocol)? = nil
    ) {
        self.localRepository = localRepository
        self.syncService = syncService
        self.locationManager = locationManager
        self.accountName = accountName
        self.coordinator = coordinator
    }

    func setCoordinator(_ coordinator: any MainCoordinatorProtocol) {
        self.coordinator = coordinator
    }

    // MARK: - Lifecycle

    /// Call from the view's `.task`.
    ///
    /// 1. Resolve location permission and centre on the viewer if granted.
    /// 2. Load the cache and paint it.
    /// 3. Start remote synchronisation.
    func start(in region: CoordinateRegion? = nil) async {
        self.region = region ?? self.region

        if case .idle = loadState { loadState = .loadingInitial }

        // Permission first: a granted location gives an initial viewport, so the
        // very first cache read is already scoped to where the viewer is.
        await requestLocationPermission()

        await loadCachedSessions()
        startSynchronizing()
    }

    /// Asks for "when in use" access. Requesting when the choice is already made
    /// is a no-op inside the manager, so this is safe on every appearance.
    func requestLocationPermission() async {
        authorization = await locationManager.requestWhenInUseAuthorization()

        guard authorization.isAuthorized else {
            // Not an error: browsing works without location, the viewer just
            // pans to an area themselves.
            return
        }
        await refreshUserLocation()
    }

    /// Resolves the viewer's position and, on first fix, centres the map there.
    func refreshUserLocation() async {
        guard let coordinate = try? await locationManager.currentLocation() else {
            userLocation = nil
            return
        }
        userLocation = coordinate

        // Only seed the viewport if the caller did not supply one, so a viewer
        // who has already panned is never yanked back to their own location.
        if region == nil {
            region = CoordinateRegion(
                center: coordinate,
                latitudeDelta: Self.defaultSpan,
                longitudeDelta: Self.defaultSpan
            )
        }
    }

    /// Roughly a 5 km window — close enough to be useful, wide enough to show
    /// more than the viewer's own street.
    private static let defaultSpan: Double = 0.05

    /// Cancels the live subscription. Pair with the view's `.onDisappear`.
    func stop() {
        syncTask?.cancel()
        syncTask = nil
    }

    /// Re-runs the query for a new viewport. Cheap to call while panning: the
    /// cache repaints immediately and the remote subscription is replaced.
    func regionDidChange(to region: CoordinateRegion) async {
        guard region != self.region else { return }
        self.region = region

        await loadCachedSessions()
        startSynchronizing()
    }

    // MARK: - Step 1–2: cache first

    /// Reads the cache and publishes it. A cache miss leaves whatever is already
    /// on screen untouched rather than blanking the map.
    private func loadCachedSessions() async {
        do {
            let cached = try await localRepository.sessions(matching: currentQuery)
            let syncedAt = try? await localRepository.lastSyncedAt()

            if !cached.isEmpty || sessions.isEmpty {
                sessions = cached
            }

            // Do not downgrade `.live` — a post-sync cache read is still live data.
            if case .live = loadState {} else {
                loadState = .showingCache(syncedAt: syncedAt)
            }
        } catch {
            // A cache failure is not user-facing while remote data may still
            // arrive; only a *total* failure surfaces, from the remote path.
            if sessions.isEmpty { loadState = .showingCache(syncedAt: nil) }
        }
    }

    // MARK: - Step 3–6: synchronise, persist, re-read

    /// Subscribes to the sync service. The service writes through to the cache;
    /// this then re-reads the cache so the map reflects persisted state rather
    /// than an in-flight remote payload.
    private func startSynchronizing() {
        syncTask?.cancel()

        let query = currentQuery
        syncTask = Task { [weak self] in
            guard let self else { return }

            do {
                for try await snapshot in syncService.sessions(matching: query) {
                    try Task.checkCancellation()
                    await apply(snapshot)
                }
            } catch is CancellationError {
                // Expected on teardown or a viewport change.
            } catch {
                // Step 7: remote failed — keep showing the cache.
                await handleSyncFailure(error)
            }
        }
    }

    private func apply(_ snapshot: PhotoSessionSnapshot) async {
        switch snapshot.origin {
        case .cache:
            // Already painted from the direct cache read; ignore to avoid a flicker.
            break

        case .remote:
            // The service has reconciled the cache, so re-read it as the single
            // source of what is displayed.
            if let reloaded = try? await localRepository.sessions(matching: currentQuery),
               !reloaded.isEmpty || snapshot.sessions.isEmpty {
                sessions = reloaded
            } else {
                sessions = snapshot.sessions
            }

            loadState = .live
            errorMessage = nil
        }
    }

    // MARK: - Step 7: degrade to cache

    /// Firestore is unavailable. The cache stays on screen and is labelled
    /// stale — the map is never cleared because the network failed.
    private func handleSyncFailure(_ error: Error) async {
        let message = (error as? LocalizedError)?.errorDescription
            ?? "Couldn't reach ShootMap. Showing saved sessions."

        if sessions.isEmpty {
            await loadCachedSessions()
        }

        let syncedAt = try? await localRepository.lastSyncedAt()
        loadState = .offline(syncedAt: syncedAt, message: message)
        errorMessage = sessions.isEmpty ? message : nil
    }

    // MARK: - User actions

    /// Pull-to-refresh. Failure leaves the cached sessions in place.
    func refresh() async {
        do {
            _ = try await syncService.refresh(matching: currentQuery)
            await loadCachedSessions()
            loadState = .live
            errorMessage = nil
        } catch {
            await handleSyncFailure(error)
        }
    }

    func showSessionDetail(for session: PhotoSession) {
        coordinator?.showSessionDetail(for: session)
    }

    /// Requests sign-out. Stops the live sync first so an in-flight Firestore
    /// listener cannot write another user's data into the cache after the
    /// session ends.
    func signOut() {
        stop()
        coordinator?.requestSignOut()
    }

    func dismissError() {
        errorMessage = nil
    }

    /// Applies a date window and re-queries both cache and remote.
    func selectFilter(_ filter: SessionDateFilter) async {
        guard filter != dateFilter else { return }
        dateFilter = filter

        await loadCachedSessions()
        startSynchronizing()
    }

    // MARK: - Query

    /// Scheduled and in-progress sessions in the current viewport and date
    /// window.
    ///
    /// There is deliberately **no lower bound at `now`**: a viewer sees every
    /// scheduled session, including ones whose date has already passed. A
    /// `nil` `dateRange` therefore means "any date", not "from now on".
    private var currentQuery: PhotoSessionQuery {
        PhotoSessionQuery(
            region: region,
            dateRange: dateFilter.dateRange(),
            statuses: [.scheduled, .ongoing]
        )
    }
}
