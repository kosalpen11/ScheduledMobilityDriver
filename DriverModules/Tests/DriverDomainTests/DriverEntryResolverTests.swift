//
//  DriverEntryResolverTests.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/5/26.
//

import DriverDomain
import XCTest

final class DriverEntryResolverTests: XCTestCase {
    func testRoutesNonDriverAccountsAwayFromHome() {
        let session = session(isDriver: false)
        let route = DriverEntryResolver().resolve(session: session, profile: nil).route
        XCTAssertEqual(route, .nonDriver)
    }

    func testRoutesMissingDriverProfile() {
        let route = DriverEntryResolver().resolve(session: session(isDriver: true), profile: nil).route
        XCTAssertEqual(route, .missingDriverProfile)
    }

    func testRoutesDriverProfilesToHomeRegardlessOfCompletionStatus() {
        let resolver = DriverEntryResolver()
        XCTAssertEqual(resolver.resolve(session: session(isDriver: true), profile: profile(status: .pending)).route, .home)
        XCTAssertEqual(resolver.resolve(session: session(isDriver: true), profile: profile(status: .documentsSubmitted)).route, .home)
        XCTAssertEqual(resolver.resolve(session: session(isDriver: true), profile: profile(status: .training)).route, .home)
        XCTAssertEqual(resolver.resolve(session: session(isDriver: true), profile: profile(status: .rejected)).route, .home)
        XCTAssertEqual(resolver.resolve(session: session(isDriver: true), profile: profile(status: .suspended)).route, .home)
        XCTAssertEqual(resolver.resolve(session: session(isDriver: true), profile: profile(status: .approved)).route, .home)
    }

    private func session(isDriver: Bool) -> AuthenticatedSession {
        AuthenticatedSession(
            user: CurrentUser(
                id: UUID(),
                phone: "+85512345678",
                fullName: nil,
                preferredLanguage: "en",
                status: .active,
                roles: isDriver ? [RoleGrant(role: .driver, scopeID: nil)] : []
            ),
            driver: nil
        )
    }

    private func profile(
        status: DriverOperationalStatus,
        readiness: DriverReadiness = DriverReadiness(missing: [], pendingReview: [], expired: [], hasActiveVehicle: true)
    ) -> DriverProfileDetail {
        DriverProfileDetail(
            id: UUID(),
            userID: UUID(),
            fullName: "Driver",
            phone: "+85512345678",
            status: status,
            nationalIDMasked: nil,
            vehicle: nil,
            documents: [],
            readiness: readiness,
            createdAt: nil
        )
    }
}
