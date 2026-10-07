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

    func testIncompleteProfileDisablesAvailabilityAndSkipsAvailabilityRepository() async throws {
        let trips = StubTripRepository(trips: [])
        let availability = StubAvailabilityRepository(availability: .available, throwsOnRead: true)
        let profile = StubDriverProfileRepository(profile: Self.incompleteProfile())
        let model = HomeViewModel(
            loadHomeSnapshot: LoadHomeSnapshotUseCase(trips: trips, availability: availability, clock: FixedClock()),
            setAvailability: SetAvailabilityUseCase(repository: availability),
            loadDriverProfile: LoadDriverProfileUseCase(repository: profile)
        )

        model.load()
        try await Task.sleep(nanoseconds: 100_000_000)

        guard case .empty(let snapshot) = model.state else {
            return XCTFail("Expected empty, got \(model.state)")
        }
        XCTAssertEqual(snapshot.availability, .unavailable)
        XCTAssertFalse(model.profileGate.allowsAvailability)
        XCTAssertEqual(model.profileGate.prompt?.actionTitle, "Complete profile")
        let availabilityReadCount = await availability.currentReadCount()
        XCTAssertEqual(availabilityReadCount, 0)
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

    private static func incompleteProfile() -> DriverProfileDetail {
        DriverProfileDetail(
            id: UUID(),
            userID: UUID(),
            fullName: "Driver",
            phone: "+85512000002",
            status: .pending,
            nationalIDMasked: nil,
            vehicle: nil,
            documents: [],
            readiness: DriverReadiness(missing: [.nationalID], pendingReview: [], expired: [], hasActiveVehicle: false),
            createdAt: nil
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
    private let throwsOnRead: Bool
    private var readCount = 0

    init(availability: DriverAvailability, throwsOnRead: Bool = false) {
        self.availability = availability
        self.throwsOnRead = throwsOnRead
    }

    func currentAvailability() async throws -> DriverAvailability {
        readCount += 1
        if throwsOnRead {
            throw TripFailure.unavailable("Availability should not be read.")
        }
        return availability
    }

    func setAvailability(_ availability: DriverAvailability) async throws -> DriverAvailability {
        self.availability = availability
        return availability
    }

    func currentReadCount() -> Int {
        readCount
    }
}

private actor StubDriverProfileRepository: DriverProfileRepository {
    private let profile: DriverProfileDetail

    init(profile: DriverProfileDetail) {
        self.profile = profile
    }

    func loadProfile() async throws -> DriverProfileDetail {
        profile
    }

    func loadDocuments() async throws -> [DriverDocument] {
        profile.documents
    }

    func uploadDocument(_ upload: DriverDocumentUpload) async throws -> DriverDocument {
        throw DriverProfileFailure.server("Unexpected upload.")
    }

    func submitOnboarding() async throws -> DriverProfileDetail {
        throw DriverProfileFailure.server("Unexpected submit.")
    }

    func clearSessionState() async {}
}
