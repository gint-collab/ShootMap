//
//  PhotoSessionTests.swift
//  ShootMapTests
//

import Testing
import Foundation
@testable import ShootMap

@Suite("PhotoSession")
struct PhotoSessionTests {

    private let calendar = Fixture.calendar
    private let now = Fixture.now

    // MARK: Valid

    @Test("A well-formed session validates")
    func validSession() throws {
        let session = Fixture.session(start: now.addingTimeInterval(3_600))
        try session.validate(calendar: calendar)
    }

    // MARK: Invalid — coordinates

    @Test("Latitude outside -90...90 is rejected")
    func invalidLatitude() {
        let session = Fixture.session(latitude: 91)
        #expect(throws: DomainValidationError.invalidLatitude(91)) {
            try session.validate(calendar: calendar)
        }
    }

    @Test("Longitude outside -180...180 is rejected")
    func invalidLongitude() {
        let session = Fixture.session(longitude: 181)
        #expect(throws: DomainValidationError.invalidLongitude(181)) {
            try session.validate(calendar: calendar)
        }
    }

    @Test("A coordinate cannot be constructed from NaN")
    func nanCoordinate() {
        #expect(throws: (any Error).self) {
            _ = try Coordinate(latitude: .nan, longitude: 0)
        }
    }

    // MARK: Invalid — time

    @Test("End time must be after start time")
    func endBeforeStart() {
        let start = now.addingTimeInterval(3_600)
        let session = Fixture.session(start: start, duration: -600)

        #expect(throws: (any Error).self) {
            try session.validate(calendar: calendar)
        }
    }

    @Test("A session shorter than the minimum is rejected")
    func tooShort() {
        let session = Fixture.session(duration: 60)  // 1 minute
        #expect(throws: (any Error).self) {
            try session.validate(calendar: calendar)
        }
    }

    @Test("A session longer than 24 hours is rejected")
    func tooLong() {
        let session = Fixture.session(duration: .days(2))
        #expect(throws: (any Error).self) {
            try session.validate(calendar: calendar)
        }
    }

    @Test("Start time must fall on the session date")
    func timesOffDate() {
        let start = now.addingTimeInterval(3_600)
        let session = PhotoSession(
            id: "s1",
            photographerId: "p1",
            photographerName: "Ansel",
            latitude: 14.5,
            longitude: 120.9,
            // Deliberately a different day from `start`.
            date: calendar.startOfDay(for: start.addingTimeInterval(.days(3))),
            startTime: start,
            endTime: start.addingTimeInterval(3_600)
        )

        #expect(throws: DomainValidationError.sessionTimesNotOnSessionDate) {
            try session.validate(calendar: calendar)
        }
    }

    // MARK: Identity

    @Test("Empty identifiers are rejected")
    func emptyIdentifiers() {
        #expect(throws: DomainValidationError.emptyIdentifier) {
            try Fixture.session(id: "   ").validate(calendar: calendar)
        }
        #expect(throws: DomainValidationError.emptyIdentifier) {
            try Fixture.session(photographerId: " ").validate(calendar: calendar)
        }
    }

    @Test("An empty photographer name is rejected")
    func emptyName() {
        #expect(throws: DomainValidationError.emptyDisplayName) {
            try Fixture.session(photographerName: "  ").validate(calendar: calendar)
        }
    }

    // MARK: Behaviour

    @Test("Only legal status transitions are allowed")
    func statusTransitions() {
        let scheduled = Fixture.session(status: .scheduled)

        #expect(scheduled.transitioned(to: .ongoing)?.status == .ongoing)
        #expect(scheduled.transitioned(to: .cancelled)?.status == .cancelled)
        // Illegal: a scheduled session cannot jump straight to completed.
        #expect(scheduled.transitioned(to: .completed) == nil)

        let cancelled = Fixture.session(status: .cancelled)
        #expect(cancelled.transitioned(to: .ongoing) == nil)
    }

    @Test("Only active sessions are map-visible")
    func mapVisibility() {
        #expect(Fixture.session(status: .scheduled).isVisibleOnMap)
        #expect(Fixture.session(status: .ongoing).isVisibleOnMap)
        #expect(!Fixture.session(status: .completed).isVisibleOnMap)
        #expect(!Fixture.session(status: .cancelled).isVisibleOnMap)
    }

    @Test("Out-of-range stored coordinates fall back to zero rather than crashing")
    func coordinateFallback() {
        #expect(Fixture.session(latitude: 999).coordinate == .zero)
    }
}
