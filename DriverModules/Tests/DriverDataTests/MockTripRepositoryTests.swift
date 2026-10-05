//
//  MockTripRepositoryTests.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/5/26.
//

import DriverData
import DriverDomain
import XCTest

final class MockTripRepositoryTests: XCTestCase {
    func testPerformPrimaryActionAdvancesStateAndVersion() async throws {
        let trip = makeTrip(status: .scheduled)
        let repository = MockTripRepository(trips: [trip])

        let updated = try await repository.perform(
            TripActionRequest(
                tripID: trip.id,
                action: .startPickup,
                expectedVersion: 3,
                idempotencyKey: "same-key"
            )
        )

        XCTAssertEqual(updated.status, .enRouteToPickup)
        XCTAssertEqual(updated.version, 4)
    }

    func testBackupActionIsRejected() async throws {
        let trip = makeTrip(assignment: .backup, status: .scheduled)
        let repository = MockTripRepository(trips: [trip])

        do {
            _ = try await repository.perform(
                TripActionRequest(
                    tripID: trip.id,
                    action: .startPickup,
                    expectedVersion: trip.version,
                    idempotencyKey: "backup"
                )
            )
            XCTFail("Expected not permitted")
        } catch let failure as TripFailure {
            XCTAssertEqual(failure, .notPermitted("Backup assignments are view-only until dispatch promotes you."))
        }
    }

    func testVersionConflictIsRejected() async throws {
        let trip = makeTrip(version: 5, status: .scheduled)
        let repository = MockTripRepository(trips: [trip])

        do {
            _ = try await repository.perform(
                TripActionRequest(
                    tripID: trip.id,
                    action: .startPickup,
                    expectedVersion: 4,
                    idempotencyKey: "conflict"
                )
            )
            XCTFail("Expected conflict")
        } catch let failure as TripFailure {
            XCTAssertEqual(failure, .conflict("Trip changed. Refreshing the latest details."))
        }
    }

    func testMissingTripReportsReassignment() async throws {
        let repository = MockTripRepository(trips: [])

        do {
            _ = try await repository.perform(
                TripActionRequest(
                    tripID: UUID(),
                    action: .startPickup,
                    expectedVersion: 1,
                    idempotencyKey: "missing"
                )
            )
            XCTFail("Expected reassigned")
        } catch let failure as TripFailure {
            XCTAssertEqual(failure, .reassigned("This trip is no longer assigned to you."))
        }
    }

    private func makeTrip(
        id: UUID = UUID(),
        version: Int = 3,
        assignment: TripAssignment = .primary,
        status: TripStatus
    ) -> ScheduledTrip {
        ScheduledTrip(
            id: id,
            version: version,
            assignment: assignment,
            status: status,
            pickupName: "Pickup",
            pickupAddress: "Pickup address",
            pickupCoordinate: Coordinate(latitude: 11.55, longitude: 104.92),
            dropoffName: "Dropoff",
            dropoffAddress: "Dropoff address",
            dropoffCoordinate: Coordinate(latitude: 11.56, longitude: 104.93),
            scheduledPickupAt: Date(timeIntervalSince1970: 0),
            passengerNote: nil
        )
    }
}
