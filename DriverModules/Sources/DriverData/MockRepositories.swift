//
//  MockRepositories.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/4/26.
//

import DriverDomain
import Foundation

public actor MockTripRepository: TripRepository {
    private var trips: [ScheduledTrip]

    public init() {
        self.trips = Self.defaultTrips()
    }

    public init(trips: [ScheduledTrip]) {
        self.trips = trips
    }

    public func upcomingTrips() async throws -> [ScheduledTrip] {
        if trips.isEmpty {
            trips = Self.defaultTrips()
        }
        return trips
    }

    public func tripDetail(id: UUID) async throws -> ScheduledTrip {
        if trips.isEmpty {
            trips = Self.defaultTrips()
        }
        guard let trip = trips.first(where: { $0.id == id }) else {
            throw TripFailure.unavailable("Trip details are not available.")
        }
        return trip
    }

    public func perform(_ request: TripActionRequest) async throws -> ScheduledTrip {
        if trips.isEmpty {
            trips = Self.defaultTrips()
        }
        guard let index = trips.firstIndex(where: { $0.id == request.tripID }) else {
            throw TripFailure.reassigned("This trip is no longer assigned to you.")
        }

        let trip = trips[index]
        guard request.expectedVersion == trip.version else {
            throw TripFailure.conflict("Trip changed. Refreshing the latest details.")
        }
        guard trip.assignment == .primary else {
            throw TripFailure.notPermitted("Backup assignments are view-only until dispatch promotes you.")
        }

        let expected = TripActionResolver().nextAction(for: trip)
        guard request.action == expected, expected != .viewDetails else {
            throw TripFailure.notPermitted("This action is not available for the current trip state.")
        }

        let updated = ScheduledTrip(
            id: trip.id,
            version: trip.version + 1,
            assignment: trip.assignment,
            status: nextStatus(after: request.action),
            pickupName: trip.pickupName,
            pickupAddress: trip.pickupAddress,
            pickupCoordinate: trip.pickupCoordinate,
            dropoffName: trip.dropoffName,
            dropoffAddress: trip.dropoffAddress,
            dropoffCoordinate: trip.dropoffCoordinate,
            scheduledPickupAt: trip.scheduledPickupAt,
            passengerNote: trip.passengerNote
        )
        trips[index] = updated
        return updated
    }

    private func nextStatus(after action: TripAction) -> TripStatus {
        switch action {
        case .startPickup:
            return .enRouteToPickup
        case .markArrived:
            return .arrivedAtPickup
        case .startTrip:
            return .inProgress
        case .completeTrip:
            return .completed
        case .viewDetails:
            return .scheduled
        }
    }

    private static func defaultTrips() -> [ScheduledTrip] {
        [
            ScheduledTrip(
                id: UUID(uuidString: "A89F1DC3-6F56-4A19-81EF-9C0F1676957B")!,
                version: 1,
                assignment: .primary,
                status: .scheduled,
                pickupName: "Sorya Center Point",
                pickupAddress: "Street 63, Phnom Penh",
                pickupCoordinate: Coordinate(latitude: 11.5686, longitude: 104.9210),
                dropoffName: "Royal University of Phnom Penh",
                dropoffAddress: "Russian Federation Blvd",
                dropoffCoordinate: Coordinate(latitude: 11.5683, longitude: 104.8900),
                scheduledPickupAt: Date(timeIntervalSinceNow: 26 * 60),
                passengerNote: "Passenger uses a folding wheelchair."
            ),
            ScheduledTrip(
                id: UUID(uuidString: "0B2E757A-C77E-4552-A051-936FD0652419")!,
                version: 1,
                assignment: .backup,
                status: .scheduled,
                pickupName: "Olympic Market",
                pickupAddress: "Street 286, Phnom Penh",
                pickupCoordinate: Coordinate(latitude: 11.5519, longitude: 104.9121),
                dropoffName: "Calmette Hospital",
                dropoffAddress: "Monivong Boulevard",
                dropoffCoordinate: Coordinate(latitude: 11.5835, longitude: 104.9154),
                scheduledPickupAt: Date(timeIntervalSinceNow: 88 * 60),
                passengerNote: nil
            )
        ]
    }
}

public actor UnavailableTripRepository: TripRepository {
    public init() {}

    public func upcomingTrips() async throws -> [ScheduledTrip] {
        throw TripFailure.unavailable("Scheduled trip APIs are not exposed by the backend yet.")
    }

    public func tripDetail(id: UUID) async throws -> ScheduledTrip {
        throw TripFailure.unavailable("Trip APIs are not exposed by the backend yet.")
    }

    public func perform(_ request: TripActionRequest) async throws -> ScheduledTrip {
        throw TripFailure.unavailable("Trip actions are not exposed by the backend yet.")
    }
}

public actor MockAvailabilityRepository: AvailabilityRepository {
    private var availability: DriverAvailability

    public init(initialAvailability: DriverAvailability = .available) {
        self.availability = initialAvailability
    }

    public func currentAvailability() async throws -> DriverAvailability {
        availability
    }

    public func setAvailability(_ availability: DriverAvailability) async throws -> DriverAvailability {
        self.availability = availability
        return availability
    }
}

public actor UnavailableAvailabilityRepository: AvailabilityRepository {
    public init() {}

    public func currentAvailability() async throws -> DriverAvailability {
        throw TripFailure.unavailable("Availability APIs are not exposed by the backend yet.")
    }

    public func setAvailability(_ availability: DriverAvailability) async throws -> DriverAvailability {
        throw TripFailure.unavailable("Availability APIs are not exposed by the backend yet.")
    }
}
