//
//  UseCases.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/4/26.
//

import Foundation

public struct LoadHomeSnapshotUseCase: Sendable {
    public let trips: any TripRepository
    public let availability: any AvailabilityRepository
    public let clock: any Clock

    public init(
        trips: any TripRepository,
        availability: any AvailabilityRepository,
        clock: any Clock = SystemClock()
    ) {
        self.trips = trips
        self.availability = availability
        self.clock = clock
    }

    public func callAsFunction(availabilityOverride: DriverAvailability? = nil) async throws -> HomeSnapshot {
        async let upcomingTrips = trips.upcomingTrips()
        let currentAvailability: DriverAvailability
        if let availabilityOverride {
            currentAvailability = availabilityOverride
        } else {
            currentAvailability = try await availability.currentAvailability()
        }

        let snapshot = try await HomeSnapshot(
            availability: currentAvailability,
            trips: upcomingTrips.sorted { $0.scheduledPickupAt < $1.scheduledPickupAt },
            loadedAt: clock.now
        )
        return snapshot
    }
}

public struct SetAvailabilityUseCase: Sendable {
    private let repository: any AvailabilityRepository

    public init(repository: any AvailabilityRepository) {
        self.repository = repository
    }

    public func callAsFunction(_ availability: DriverAvailability) async throws -> DriverAvailability {
        try await repository.setAvailability(availability)
    }
}

public struct LoadTripDetailUseCase: Sendable {
    private let repository: any TripRepository

    public init(repository: any TripRepository) {
        self.repository = repository
    }

    public func callAsFunction(id: UUID) async throws -> ScheduledTrip {
        try await repository.tripDetail(id: id)
    }
}

public struct PerformTripActionUseCase: Sendable {
    private let repository: any TripRepository

    public init(repository: any TripRepository) {
        self.repository = repository
    }

    public func callAsFunction(_ request: TripActionRequest) async throws -> ScheduledTrip {
        try await repository.perform(request)
    }
}

public struct HomeSnapshot: Equatable, Sendable {
    public let availability: DriverAvailability
    public let trips: [ScheduledTrip]
    public let loadedAt: Date

    public init(availability: DriverAvailability, trips: [ScheduledTrip], loadedAt: Date) {
        self.availability = availability
        self.trips = trips
        self.loadedAt = loadedAt
    }

    public var nextTrip: ScheduledTrip? {
        trips.first
    }
}

public struct TripActionResolver: Sendable {
    public init() {}

    public func nextAction(for trip: ScheduledTrip) -> TripAction {
        guard trip.assignment == .primary else {
            return .viewDetails
        }
        switch trip.status {
        case .scheduled:
            return .startPickup
        case .enRouteToPickup:
            return .markArrived
        case .arrivedAtPickup:
            return .startTrip
        case .inProgress:
            return .completeTrip
        case .completed, .cancelled, .reassigned:
            return .viewDetails
        }
    }

    public func isActionPermitted(_ action: TripAction, for trip: ScheduledTrip) -> Bool {
        action != .viewDetails && action == nextAction(for: trip)
    }
}
