//
//  DriverModels.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/4/26.
//

import Foundation

public struct DriverProfile: Equatable, Sendable {
    public let id: UUID
    public let displayName: String
    public let approvalStatus: DriverApprovalStatus

    public init(id: UUID, displayName: String, approvalStatus: DriverApprovalStatus) {
        self.id = id
        self.displayName = displayName
        self.approvalStatus = approvalStatus
    }
}

public enum DriverApprovalStatus: Equatable, Sendable {
    case approved
    case pendingReview
    case rejected(reason: String?)
}

public enum DriverAvailability: Equatable, Sendable {
    case unavailable
    case available
}

public struct Coordinate: Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

public struct ScheduledTrip: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let version: Int
    public let assignment: TripAssignment
    public let status: TripStatus
    public let pickupName: String
    public let pickupAddress: String
    public let pickupCoordinate: Coordinate
    public let dropoffName: String
    public let dropoffAddress: String
    public let dropoffCoordinate: Coordinate
    public let scheduledPickupAt: Date
    public let passengerNote: String?

    public init(
        id: UUID,
        version: Int = 1,
        assignment: TripAssignment,
        status: TripStatus,
        pickupName: String,
        pickupAddress: String,
        pickupCoordinate: Coordinate,
        dropoffName: String,
        dropoffAddress: String,
        dropoffCoordinate: Coordinate,
        scheduledPickupAt: Date,
        passengerNote: String?
    ) {
        self.id = id
        self.version = version
        self.assignment = assignment
        self.status = status
        self.pickupName = pickupName
        self.pickupAddress = pickupAddress
        self.pickupCoordinate = pickupCoordinate
        self.dropoffName = dropoffName
        self.dropoffAddress = dropoffAddress
        self.dropoffCoordinate = dropoffCoordinate
        self.scheduledPickupAt = scheduledPickupAt
        self.passengerNote = passengerNote
    }
}

public enum TripAssignment: Equatable, Sendable {
    case primary
    case backup
}

public enum TripStatus: Equatable, Sendable {
    case scheduled
    case enRouteToPickup
    case arrivedAtPickup
    case inProgress
    case completed
    case cancelled
    case reassigned
}

public enum TripAction: Equatable, Sendable {
    case viewDetails
    case startPickup
    case markArrived
    case startTrip
    case completeTrip
}

public struct TripActionRequest: Equatable, Sendable {
    public let tripID: UUID
    public let action: TripAction
    public let expectedVersion: Int
    public let idempotencyKey: String

    public init(tripID: UUID, action: TripAction, expectedVersion: Int, idempotencyKey: String) {
        self.tripID = tripID
        self.action = action
        self.expectedVersion = expectedVersion
        self.idempotencyKey = idempotencyKey
    }
}

public enum TripFailure: Error, Equatable, Sendable {
    case unavailable(String)
    case notPermitted(String)
    case conflict(String)
    case cancelled(String)
    case reassigned(String)
    case transient(String)
    case server(String)
}
