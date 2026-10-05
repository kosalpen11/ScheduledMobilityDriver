//
//  TripDetailViewModelTests.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/5/26.
//

import DriverDomain
import DriverPresentation
import XCTest

@MainActor
final class TripDetailViewModelTests: XCTestCase {
    func testDuplicateActionSubmissionIsIgnoredWhileInFlight() async {
        let repository = SlowTripRepository(trip: Self.trip())
        let model = TripDetailViewModel(
            tripID: Self.tripID,
            loadTrip: LoadTripDetailUseCase(repository: repository),
            performAction: PerformTripActionUseCase(repository: repository)
        )

        await model.load()
        async let first = model.performPrimaryAction()
        async let second = model.performPrimaryAction()
        _ = await (first, second)

        let count = await repository.currentPerformCount()
        XCTAssertEqual(count, 1)
    }

    func testConflictRefreshesAndPreservesContent() async {
        let repository = SlowTripRepository(trip: Self.trip(), performError: .conflict("Trip changed. Refreshing the latest details."))
        let model = TripDetailViewModel(
            tripID: Self.tripID,
            loadTrip: LoadTripDetailUseCase(repository: repository),
            performAction: PerformTripActionUseCase(repository: repository)
        )

        await model.load()
        _ = await model.performPrimaryAction()

        guard case .recoverableError(let presentation, let message) = model.state else {
            return XCTFail("Expected recoverable error")
        }
        XCTAssertEqual(presentation.trip.id, Self.tripID)
        XCTAssertEqual(message, "Trip changed. Refreshing the latest details.")
    }

    private static let tripID = UUID(uuidString: "A89F1DC3-6F56-4A19-81EF-9C0F1676957B")!

    private static func trip() -> ScheduledTrip {
        ScheduledTrip(
            id: tripID,
            version: 1,
            assignment: .primary,
            status: .scheduled,
            pickupName: "Pickup",
            pickupAddress: "Pickup address",
            pickupCoordinate: Coordinate(latitude: 11.55, longitude: 104.92),
            dropoffName: "Dropoff",
            dropoffAddress: "Dropoff address",
            dropoffCoordinate: Coordinate(latitude: 11.56, longitude: 104.93),
            scheduledPickupAt: Date(timeIntervalSince1970: 0),
            passengerNote: "Bring ramp."
        )
    }
}

private actor SlowTripRepository: TripRepository {
    private var trip: ScheduledTrip
    private let performError: TripFailure?
    private var performCount = 0

    init(trip: ScheduledTrip, performError: TripFailure? = nil) {
        self.trip = trip
        self.performError = performError
    }

    func upcomingTrips() async throws -> [ScheduledTrip] {
        [trip]
    }

    func tripDetail(id: UUID) async throws -> ScheduledTrip {
        trip
    }

    func perform(_ request: TripActionRequest) async throws -> ScheduledTrip {
        performCount += 1
        try await Task.sleep(nanoseconds: 60_000_000)
        if let performError {
            throw performError
        }
        trip = ScheduledTrip(
            id: trip.id,
            version: trip.version + 1,
            assignment: trip.assignment,
            status: .enRouteToPickup,
            pickupName: trip.pickupName,
            pickupAddress: trip.pickupAddress,
            pickupCoordinate: trip.pickupCoordinate,
            dropoffName: trip.dropoffName,
            dropoffAddress: trip.dropoffAddress,
            dropoffCoordinate: trip.dropoffCoordinate,
            scheduledPickupAt: trip.scheduledPickupAt,
            passengerNote: trip.passengerNote
        )
        return trip
    }

    func currentPerformCount() -> Int {
        performCount
    }
}
