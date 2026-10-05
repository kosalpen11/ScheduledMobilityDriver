//
//  TripActionResolverTests.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/4/26.
//

import DriverDomain
import XCTest

final class TripActionResolverTests: XCTestCase {
    func testNextActionFollowsTripStatus() {
        let resolver = TripActionResolver()

        XCTAssertEqual(resolver.nextAction(for: trip(status: .scheduled)), .startPickup)
        XCTAssertEqual(resolver.nextAction(for: trip(status: .enRouteToPickup)), .markArrived)
        XCTAssertEqual(resolver.nextAction(for: trip(status: .arrivedAtPickup)), .startTrip)
        XCTAssertEqual(resolver.nextAction(for: trip(status: .inProgress)), .completeTrip)
        XCTAssertEqual(resolver.nextAction(for: trip(status: .completed)), .viewDetails)
        XCTAssertEqual(resolver.nextAction(for: trip(status: .cancelled)), .viewDetails)
        XCTAssertEqual(resolver.nextAction(for: trip(status: .reassigned)), .viewDetails)
    }

    func testBackupAssignmentsAreViewOnly() {
        let resolver = TripActionResolver()
        let backup = trip(assignment: .backup, status: .scheduled)

        XCTAssertEqual(resolver.nextAction(for: backup), .viewDetails)
        XCTAssertFalse(resolver.isActionPermitted(.startPickup, for: backup))
    }

    func testPrimaryCurrentActionIsPermitted() {
        let resolver = TripActionResolver()
        let primary = trip(status: .scheduled)

        XCTAssertTrue(resolver.isActionPermitted(.startPickup, for: primary))
        XCTAssertFalse(resolver.isActionPermitted(.completeTrip, for: primary))
    }

    private func trip(assignment: TripAssignment = .primary, status: TripStatus) -> ScheduledTrip {
        ScheduledTrip(
            id: UUID(),
            assignment: assignment,
            status: status,
            pickupName: "Pickup",
            pickupAddress: "Pickup address",
            pickupCoordinate: Coordinate(latitude: 0, longitude: 0),
            dropoffName: "Dropoff",
            dropoffAddress: "Dropoff address",
            dropoffCoordinate: Coordinate(latitude: 1, longitude: 1),
            scheduledPickupAt: Date(timeIntervalSince1970: 0),
            passengerNote: nil
        )
    }
}
