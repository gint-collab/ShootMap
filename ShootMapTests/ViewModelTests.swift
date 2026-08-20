//
//  ViewModelTests.swift
//  ShootMapTests
//

import Testing
import Foundation
@testable import ShootMap

// MARK: - Login

@MainActor
@Suite("LoginViewModel")
struct LoginViewModelTests {

    private func makeSUT() -> (LoginViewModel, MockAuthRepository, SpyAuthNavigator) {
        let auth = MockAuthRepository()
        let navigator = SpyAuthNavigator()
        let sut = LoginViewModel(authRepository: auth, navigator: navigator)
        return (sut, auth, navigator)
    }

    @Test("Successful login reports the user to the coordinator")
    func successfulLogin() async {
        let (sut, auth, navigator) = makeSUT()
        let user = Fixture.viewer()
        auth.signInResult = .success(user)

        sut.email = "viewer@example.com"
        sut.password = "correct-horse"

        await sut.login()

        #expect(auth.signInCallCount == 1)
        #expect(auth.lastCredentials?.email == "viewer@example.com")
        #expect(navigator.authenticatedUsers.map(\.id) == [user.id])
        #expect(sut.errorMessage == nil)
        #expect(!sut.isLoading)
        // The credential must not linger in memory after use.
        #expect(sut.password.isEmpty)
    }

    @Test("Failed login surfaces an error and does not navigate")
    func failedLogin() async {
        let (sut, auth, navigator) = makeSUT()
        auth.signInResult = .failure(AuthError.invalidCredentials)

        sut.email = "viewer@example.com"
        sut.password = "wrong"

        await sut.login()

        #expect(sut.errorMessage != nil)
        #expect(navigator.authenticatedUsers.isEmpty)
        #expect(!sut.isLoading)
    }

    @Test("An incomplete form cannot be submitted")
    func submissionGuard() async {
        let (sut, auth, _) = makeSUT()

        sut.email = ""
        sut.password = ""
        #expect(!sut.canSubmit)

        await sut.login()
        #expect(auth.signInCallCount == 0)
    }

    @Test("Editing the form clears a stale error")
    func errorClearsOnEdit() async {
        let (sut, auth, _) = makeSUT()
        auth.signInResult = .failure(AuthError.invalidCredentials)
        sut.email = "viewer@example.com"
        sut.password = "wrong"
        await sut.login()
        #expect(sut.errorMessage != nil)

        sut.email = "viewer2@example.com"
        #expect(sut.errorMessage == nil)
    }

    @Test("Navigation to sign up is delegated, not performed")
    func navigatesToSignUp() {
        let (sut, _, navigator) = makeSUT()
        sut.showSignUp()
        #expect(navigator.showSignUpCount == 1)
    }
}

// MARK: - Create session

@MainActor
@Suite("CreateSessionViewModel")
struct CreateSessionViewModelTests {

    private func makeSUT(
        coordinate: Coordinate? = try! Coordinate(latitude: 14.5995, longitude: 120.9842),
        author: User? = Fixture.photographer()
    ) -> (CreateSessionViewModel, MockPhotoSessionRepository, MockAuthRepository, SpyMainCoordinator) {
        let remote = MockPhotoSessionRepository()
        let auth = MockAuthRepository()
        auth.storedUser = author
        let coordinator = SpyMainCoordinator()

        let sut = CreateSessionViewModel(
            selectedCoordinate: coordinate,
            sessionRepository: remote,
            authRepository: auth,
            coordinator: coordinator,
            calendar: Fixture.calendar,
            now: Fixture.now
        )
        return (sut, remote, auth, coordinator)
    }

    @Test("Successful creation publishes once and notifies the coordinator")
    func successfulCreation() async {
        let (sut, remote, _, coordinator) = makeSUT()

        await sut.save()

        #expect(remote.publishedSessions.count == 1)
        #expect(coordinator.finishedSessions.count == 1)
        #expect(sut.errorMessage == nil)
        #expect(!sut.isSaving)

        let published = try! #require(remote.publishedSessions.first)
        // Authorship is derived from the signed-in user, never the form.
        #expect(published.photographerId == Fixture.photographer().id)
        #expect(published.status == .scheduled)
    }

    @Test("Publishing without a location fails and does not navigate")
    func missingLocation() async {
        let (sut, remote, _, coordinator) = makeSUT(coordinate: nil)

        #expect(!sut.canSave)
        await sut.save()

        #expect(remote.publishedSessions.isEmpty)
        #expect(coordinator.finishedSessions.isEmpty)
        #expect(sut.errorMessage != nil)
    }

    @Test("An invalid time range is rejected before any network call")
    func invalidTimeRange() async {
        let (sut, remote, _, coordinator) = makeSUT()

        // End before start — impossible via the UI, but the guard must hold.
        sut.endTime = sut.startTime.addingTimeInterval(-3_600)

        await sut.save()

        #expect(remote.publishedSessions.isEmpty)
        #expect(coordinator.finishedSessions.isEmpty)
        #expect(sut.errorMessage != nil)
    }

    @Test("A signed-out user cannot publish")
    func notAuthenticated() async {
        let (sut, remote, _, coordinator) = makeSUT(author: nil)

        await sut.save()

        #expect(remote.publishedSessions.isEmpty)
        #expect(coordinator.finishedSessions.isEmpty)
        #expect(sut.errorMessage == AuthErrorText.notAuthenticated)
    }

    @Test("A viewer cannot publish")
    func viewerCannotPublish() async {
        let (sut, remote, _, _) = makeSUT(author: Fixture.viewer())

        await sut.save()

        #expect(remote.publishedSessions.isEmpty)
        #expect(sut.errorMessage != nil)
    }

    @Test("A Firestore failure surfaces an error and does not navigate")
    func remoteFailure() async {
        let (sut, remote, _, coordinator) = makeSUT()
        remote.publishError = TestError.network

        await sut.save()

        #expect(coordinator.finishedSessions.isEmpty)
        #expect(sut.errorMessage == TestError.network.errorDescription)
        #expect(!sut.isSaving)
    }

    @Test("Moving the start time keeps the end time after it")
    func startTimeKeepsRangeValid() {
        let (sut, _, _, _) = makeSUT()

        sut.startTime = sut.endTime.addingTimeInterval(3_600)
        sut.startTimeDidChange()

        #expect(sut.endTime > sut.startTime)
    }

    @Test("Cancelling delegates to the coordinator")
    func cancel() {
        let (sut, _, _, coordinator) = makeSUT()
        sut.cancel()
        #expect(coordinator.cancelCount == 1)
    }

    @Test("An out-of-range tap clears the selection instead of storing it")
    func invalidCoordinateRejected() {
        let (sut, _, _, _) = makeSUT()

        sut.selectCoordinate(latitude: 200, longitude: 0)

        #expect(sut.selectedCoordinate == nil)
        #expect(sut.errorMessage != nil)
    }
}

/// Expected copy, so the assertion above does not restate the implementation.
private enum AuthErrorText {
    static let notAuthenticated = PhotoSessionError.notAuthenticated.errorDescription
}

// MARK: - Photographer map

@MainActor
@Suite("PhotographerMapViewModel")
struct PhotographerMapViewModelTests {

    private func makeSUT(
        sessions: [PhotoSession] = [],
        authorization: LocationAuthorization = .whenInUse
    ) -> (PhotographerMapViewModel, MockLocationManager, MockPhotoSessionRepository, SpyMainCoordinator) {
        let location = MockLocationManager()
        location.authorization = authorization

        let repository = MockPhotoSessionRepository()
        repository.sessions = sessions

        let coordinator = SpyMainCoordinator()

        let sut = PhotographerMapViewModel(
            photographerId: "photographer-1",
            locationManager: location,
            sessionRepository: repository,
            coordinator: coordinator
        )
        return (sut, location, repository, coordinator)
    }

    @Test("Appearing requests permission and loads the photographer's sessions")
    func onAppear() async {
        let session = Fixture.session()
        let (sut, location, _, _) = makeSUT(sessions: [session])

        await sut.onAppear()

        #expect(location.requestAuthorizationCallCount == 1)
        #expect(sut.mySessions.map(\.id) == [session.id])
        #expect(sut.userLocation != nil)
    }

    @Test("Denied location still allows manual pin selection")
    func deniedLocation() async {
        let (sut, _, _, _) = makeSUT(authorization: .denied)

        await sut.onAppear()

        #expect(sut.isLocationDenied)
        #expect(sut.userLocation == nil)

        sut.selectCoordinate(latitude: 14.6, longitude: 120.9)
        #expect(sut.hasSelection)
    }

    @Test("An invalid coordinate is never stored")
    func invalidSelection() async {
        let (sut, _, _, _) = makeSUT()

        sut.selectCoordinate(latitude: -91, longitude: 0)

        #expect(sut.selectedCoordinate == nil)
        #expect(sut.errorMessage != nil)
    }

    @Test("Creating a session requires a pin")
    func createRequiresPin() async {
        let (sut, _, _, coordinator) = makeSUT()

        sut.createSessionAtSelectedLocation()
        #expect(coordinator.createSessionCount == 0)
        #expect(sut.errorMessage != nil)

        sut.selectCoordinate(latitude: 14.6, longitude: 120.9)
        sut.createSessionAtSelectedLocation()
        #expect(coordinator.createSessionCount == 1)
    }

    @Test("The selected pin is carried into the create screen")
    func pinTravelsToComposer() {
        let (sut, _, _, coordinator) = makeSUT()

        sut.selectCoordinate(latitude: 14.6, longitude: 120.9)
        sut.createSessionAtSelectedLocation()

        // Regression guard: opening the composer with `nil` here is what made
        // it report "No location chosen".
        let delivered = coordinator.createSessionCoordinates.first ?? nil
        #expect(delivered?.latitude == 14.6)
        #expect(delivered?.longitude == 120.9)
    }

    @Test("Tapping a session pin navigates to its detail")
    func navigatesToDetail() {
        let session = Fixture.session()
        let (sut, _, _, coordinator) = makeSUT()

        sut.showSessionDetail(for: session)

        #expect(coordinator.detailSessionIds == [session.id])
    }

    @Test("A load failure keeps previously loaded sessions on screen")
    func loadFailureKeepsData() async {
        let session = Fixture.session()
        let (sut, _, repository, _) = makeSUT(sessions: [session])

        await sut.loadMySessions()
        #expect(sut.mySessions.count == 1)

        repository.fetchError = TestError.network
        await sut.loadMySessions()

        #expect(sut.mySessions.count == 1)     // not blanked
        #expect(sut.errorMessage != nil)
    }
}

// MARK: - Session detail

@MainActor
@Suite("SessionDetailViewModel")
struct SessionDetailViewModelTests {

    private func makeSUT(
        session: PhotoSession = Fixture.session(photographerId: "owner-1"),
        currentUserId: String = "owner-1"
    ) -> (SessionDetailViewModel, MockPhotoSessionRepository, MockLocalPhotoSessionRepository) {
        let remote = MockPhotoSessionRepository()
        remote.sessions = [session]
        let local = MockLocalPhotoSessionRepository(seed: [session])

        let sut = SessionDetailViewModel(
            session: session,
            localRepository: local,
            remoteRepository: remote,
            sessionWriter: remote,
            currentUserId: currentUserId,
            coordinator: SpyMainCoordinator()
        )
        return (sut, remote, local)
    }

    @Test("The owner is offered only legal transitions")
    func ownerSeesLegalTransitions() {
        let (sut, _, _) = makeSUT(
            session: Fixture.session(photographerId: "owner-1", status: .scheduled)
        )

        #expect(sut.isOwner)
        // From `scheduled` the domain permits ongoing and cancelled only.
        #expect(Set(sut.availableStatusTransitions) == [.ongoing, .cancelled])
    }

    @Test("A non-owner is offered no transitions")
    func viewerSeesNoTransitions() {
        let (sut, _, _) = makeSUT(currentUserId: "someone-else")

        #expect(!sut.isOwner)
        #expect(sut.availableStatusTransitions.isEmpty)
        #expect(!sut.canChangeStatus)
    }

    @Test("A terminal session offers no further transitions")
    func terminalStatusIsFinal() {
        let (sut, _, _) = makeSUT(
            session: Fixture.session(photographerId: "owner-1", status: .completed)
        )

        #expect(sut.availableStatusTransitions.isEmpty)
    }

    @Test("Changing status updates the session and the cache")
    func updateStatusSucceeds() async {
        let session = Fixture.session(id: "s1", photographerId: "owner-1", status: .scheduled)
        let (sut, remote, local) = makeSUT(session: session)

        await sut.updateStatus(to: .ongoing)

        #expect(sut.session?.status == .ongoing)
        #expect(remote.sessions.first?.status == .ongoing)
        #expect(local.storage["s1"]?.status == .ongoing)
        #expect(sut.errorMessage == nil)
        #expect(!sut.isUpdatingStatus)
    }

    @Test("An illegal transition is refused before any network call")
    func illegalTransitionRefused() async {
        let session = Fixture.session(id: "s1", photographerId: "owner-1", status: .scheduled)
        let (sut, remote, _) = makeSUT(session: session)

        // scheduled → completed is not a legal move.
        await sut.updateStatus(to: .completed)

        #expect(sut.session?.status == .scheduled)
        #expect(remote.sessions.first?.status == .scheduled)
        #expect(sut.errorMessage != nil)
    }

    @Test("A non-owner cannot change status")
    func nonOwnerCannotChangeStatus() async {
        let session = Fixture.session(id: "s1", photographerId: "owner-1", status: .scheduled)
        let (sut, remote, _) = makeSUT(session: session, currentUserId: "intruder")

        await sut.updateStatus(to: .cancelled)

        #expect(remote.sessions.first?.status == .scheduled)
        #expect(sut.errorMessage == PhotoSessionError.notSessionOwner.errorDescription)
    }
}

// MARK: - Viewer map

@MainActor
@Suite("ViewerMapViewModel")
struct ViewerMapViewModelTests {

    private func makeSUT(
        cached: [PhotoSession] = [],
        syncStamp: Date? = nil,
        authorization: LocationAuthorization = .whenInUse
    ) -> (ViewerMapViewModel, MockLocalPhotoSessionRepository, MockSyncService, SpyMainCoordinator) {
        let local = MockLocalPhotoSessionRepository(seed: cached, syncStamp: syncStamp)
        let sync = MockSyncService()
        let location = MockLocationManager()
        location.authorization = authorization
        let coordinator = SpyMainCoordinator()
        let sut = ViewerMapViewModel(
            localRepository: local,
            syncService: sync,
            locationManager: location,
            coordinator: coordinator
        )
        return (sut, local, sync, coordinator)
    }

    @Test("Starting asks for location permission and centres on the viewer")
    func requestsLocationPermission() async {
        let (sut, _, _, _) = makeSUT()

        await sut.start()

        #expect(sut.isLocationAvailable)
        #expect(sut.userLocation != nil)
        // A granted location seeds the first viewport.
        #expect(sut.region != nil)
    }

    @Test("Denied location still allows browsing")
    func deniedLocationStillBrowses() async {
        let cached = Fixture.session(id: "cached")
        let (sut, _, _, _) = makeSUT(cached: [cached], authorization: .denied)

        await sut.start(in: Fixture.manila)

        #expect(sut.isLocationDenied)
        #expect(!sut.isLocationAvailable)
        #expect(sut.userLocation == nil)
        // Sessions still load — permission is never a gate on browsing.
        #expect(sut.sessions.map(\.id) == ["cached"])
    }

    @Test("An explicit region is not overridden by the user's location")
    func explicitRegionWins() async {
        let (sut, _, _, _) = makeSUT()

        await sut.start(in: Fixture.manila)

        #expect(sut.region == Fixture.manila)
    }

    @Test("Cached sessions are shown before any remote data arrives")
    func cacheFirst() async {
        let cached = Fixture.session(id: "cached")
        let (sut, _, _, _) = makeSUT(cached: [cached], syncStamp: Fixture.now)

        await sut.start(in: Fixture.manila)

        #expect(sut.sessions.map(\.id) == ["cached"])
    }

    @Test("A remote snapshot re-reads the cache and marks the data live")
    func syncUpdatesFromCache() async {
        let cached = Fixture.session(id: "cached")
        let fresh = Fixture.session(id: "fresh")
        let (sut, local, sync, _) = makeSUT(cached: [cached])

        // The service reconciles the cache, so the ViewModel should read it back.
        local.storage[fresh.id] = fresh
        sync.snapshots = [
            PhotoSessionSnapshot(sessions: [cached, fresh], origin: .remote, syncedAt: Fixture.now)
        ]

        await sut.start(in: Fixture.manila)
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(50))

        #expect(Set(sut.sessions.map(\.id)) == ["cached", "fresh"])
        #expect(sut.loadState == .live)
    }

    @Test("Offline: a remote failure keeps cached sessions and flags staleness")
    func offlineKeepsCache() async {
        let cached = Fixture.session(id: "cached")
        let (sut, _, sync, _) = makeSUT(cached: [cached], syncStamp: Fixture.now)
        sync.streamError = TestError.network

        await sut.start(in: Fixture.manila)
        try? await Task.sleep(for: .milliseconds(50))

        #expect(sut.sessions.map(\.id) == ["cached"])   // never blanked
        #expect(sut.isShowingStaleData)
        // Data is on screen, so no blocking error is shown.
        #expect(sut.errorMessage == nil)
    }

    @Test("A cache failure with no data leaves the map empty rather than crashing")
    func cacheFailure() async {
        let (sut, local, _, _) = makeSUT()
        local.readError = TestError.cache

        await sut.start(in: Fixture.manila)

        #expect(sut.sessions.isEmpty)
    }

    @Test("Date filters change the queried window", arguments: [
        SessionDateFilter.all,
        .today,
        .yesterday,
        .lastWeek
    ])
    func dateFilters(filter: SessionDateFilter) async {
        let (sut, _, _, _) = makeSUT()

        await sut.selectFilter(filter)

        #expect(sut.dateFilter == filter)
    }

    @Test("Past scheduled sessions are still visible to viewers")
    func pastSessionsRemainVisible() async {
        let past = Fixture.session(
            id: "last-week",
            start: Fixture.now.addingTimeInterval(-.days(7))
        )
        let upcoming = Fixture.session(
            id: "next-week",
            start: Fixture.now.addingTimeInterval(.days(7))
        )
        let (sut, _, _, _) = makeSUT(cached: [past, upcoming])

        await sut.start(in: Fixture.manila)

        // "All" must not hide a session simply because its date has passed.
        #expect(Set(sut.sessions.map(\.id)) == ["last-week", "next-week"])
    }

    @Test("Today's window includes sessions that already finished today")
    func todayIncludesEarlierToday() {
        let now = Fixture.now
        let calendar = Fixture.calendar
        let window = try! #require(SessionDateFilter.today.dateRange(now: now, calendar: calendar))

        #expect(window.lowerBound == calendar.startOfDay(for: now))
        #expect(window.contains(calendar.startOfDay(for: now)))
    }

    @Test("Yesterday sits entirely before today, with no overlap")
    func pastWindowsDoNotOverlap() {
        let now = Fixture.now
        let calendar = Fixture.calendar

        let today = try! #require(SessionDateFilter.today.dateRange(now: now, calendar: calendar))
        let yesterday = try! #require(SessionDateFilter.yesterday.dateRange(now: now, calendar: calendar))

        // Both windows look backwards, and neither claims the other's days.
        #expect(yesterday.upperBound < today.lowerBound)
        #expect(!yesterday.contains(now))
        #expect(!today.contains(yesterday.lowerBound))

        #expect(SessionDateFilter.all.dateRange(now: now, calendar: calendar) == nil)
    }

    @Test("Last week is a rolling seven days ending today")
    func lastWeekIsRollingSevenDays() {
        let now = Fixture.now
        let calendar = Fixture.calendar

        let today = try! #require(SessionDateFilter.today.dateRange(now: now, calendar: calendar))
        let yesterday = try! #require(SessionDateFilter.yesterday.dateRange(now: now, calendar: calendar))
        let lastWeek = try! #require(SessionDateFilter.lastWeek.dateRange(now: now, calendar: calendar))

        // The window ends today, so it contains today and yesterday …
        #expect(lastWeek.upperBound == today.upperBound)
        #expect(lastWeek.contains(now))
        #expect(lastWeek.contains(yesterday.lowerBound))

        // … and starts at midnight six days back, giving seven whole days.
        let expectedStart = calendar.startOfDay(for: now.addingTimeInterval(-.days(6)))
        #expect(lastWeek.lowerBound == expectedStart)

        // Anything older than the window falls outside it.
        #expect(!lastWeek.contains(expectedStart.addingTimeInterval(-1)))
    }

    @Test("Yesterday's window covers that whole calendar day")
    func yesterdayCoversFullDay() {
        let now = Fixture.now
        let calendar = Fixture.calendar
        let yesterday = try! #require(SessionDateFilter.yesterday.dateRange(now: now, calendar: calendar))

        let expectedStart = calendar.startOfDay(for: now.addingTimeInterval(-.days(1)))
        #expect(yesterday.lowerBound == expectedStart)
        // A shoot at midday yesterday is inside the window.
        #expect(yesterday.contains(expectedStart.addingTimeInterval(.hours(12))))
    }

    @Test("Selecting a pin navigates to the session detail")
    func navigation() {
        let session = Fixture.session()
        let (sut, _, _, coordinator) = makeSUT()

        sut.showSessionDetail(for: session)

        #expect(coordinator.detailSessionIds == [session.id])
    }

    @Test("Pull-to-refresh failure retains cached sessions")
    func refreshFailure() async {
        let cached = Fixture.session(id: "cached")
        let (sut, _, sync, _) = makeSUT(cached: [cached], syncStamp: Fixture.now)
        sync.refreshResult = .failure(TestError.network)

        await sut.start(in: Fixture.manila)
        await sut.refresh()

        #expect(sut.sessions.map(\.id) == ["cached"])
        #expect(sut.isShowingStaleData)
    }
}
