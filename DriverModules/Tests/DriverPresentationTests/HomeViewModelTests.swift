//
//  HomeViewModelTests.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/4/26.
//

import DriverDomain
import DriverPresentation
import XCTest

@MainActor
final class HomeViewModelTests: XCTestCase {
    func testLoadShowsSortedContent() async throws {
        let trips = StubTripRepository(trips: [
            trip(id: "AE8F0F11-3801-4F44-8135-E0F449D5DAF0", offset: 20),
            trip(id: "E733776B-E043-4E26-BDBB-4B2379147384", offset: 5)
        ])
        let availability = StubAvailabilityRepository(availability: .available)
        let model = HomeViewModel(
            loadHomeSnapshot: LoadHomeSnapshotUseCase(trips: trips, availability: availability, clock: FixedClock()),
            setAvailability: SetAvailabilityUseCase(repository: availability)
        )

        model.load()
        try await Task.sleep(nanoseconds: 100_000_000)

        guard case .content(let snapshot) = model.state else {
            return XCTFail("Expected content, got \(model.state)")
        }
        XCTAssertEqual(snapshot.trips.map(\.id.uuidString), [
            "E733776B-E043-4E26-BDBB-4B2379147384",
            "AE8F0F11-3801-4F44-8135-E0F449D5DAF0"
        ])
    }

    private func trip(id: String, offset: TimeInterval) -> ScheduledTrip {
        ScheduledTrip(
            id: UUID(uuidString: id)!,
            assignment: .primary,
            status: .scheduled,
            pickupName: "Pickup",
            pickupAddress: "Pickup address",
            pickupCoordinate: Coordinate(latitude: 0, longitude: 0),
            dropoffName: "Dropoff",
            dropoffAddress: "Dropoff address",
            dropoffCoordinate: Coordinate(latitude: 1, longitude: 1),
            scheduledPickupAt: Date(timeIntervalSince1970: offset),
            passengerNote: nil
        )
    }
}

private struct FixedClock: Clock {
    var now: Date { Date(timeIntervalSince1970: 0) }
}

private actor StubTripRepository: TripRepository {
    let trips: [ScheduledTrip]

    init(trips: [ScheduledTrip]) {
        self.trips = trips
    }

    func upcomingTrips() async throws -> [ScheduledTrip] {
        trips
    }

    func tripDetail(id: UUID) async throws -> ScheduledTrip {
        trips.first { $0.id == id }!
    }

    func perform(_ request: TripActionRequest) async throws -> ScheduledTrip {
        try await tripDetail(id: request.tripID)
    }
}

private actor StubAvailabilityRepository: AvailabilityRepository {
    private var availability: DriverAvailability

    init(availability: DriverAvailability) {
        self.availability = availability
    }

    func currentAvailability() async throws -> DriverAvailability {
        availability
    }

    func setAvailability(_ availability: DriverAvailability) async throws -> DriverAvailability {
        self.availability = availability
        return availability
    }
}
