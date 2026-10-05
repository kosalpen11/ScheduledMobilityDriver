//
//  Repositories.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/4/26.
//

import Foundation

public protocol DriverSessionRepository: Sendable {
    func restoreSession() async throws -> DriverProfile?
}

public protocol TripRepository: Sendable {
    func upcomingTrips() async throws -> [ScheduledTrip]
    func tripDetail(id: UUID) async throws -> ScheduledTrip
    func perform(_ request: TripActionRequest) async throws -> ScheduledTrip
}

public protocol AvailabilityRepository: Sendable {
    func currentAvailability() async throws -> DriverAvailability
    func setAvailability(_ availability: DriverAvailability) async throws -> DriverAvailability
}

public protocol Clock: Sendable {
    var now: Date { get }
}

public struct SystemClock: Clock {
    public init() {}

    public var now: Date {
        Date()
    }
}
