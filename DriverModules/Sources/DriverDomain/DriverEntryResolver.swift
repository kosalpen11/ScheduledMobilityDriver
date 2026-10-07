//
//  DriverEntryResolver.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/5/26.
//

import Foundation

public enum DriverEntryRoute: Equatable, Sendable {
    case home
    case onboarding
    case applicationReview
    case training
    case rejected
    case suspended
    case readiness
    case nonDriver
    case missingDriverProfile
}

public struct DriverEntryResolution: Equatable, Sendable {
    public let route: DriverEntryRoute
    public let profile: DriverProfileDetail?

    public init(route: DriverEntryRoute, profile: DriverProfileDetail?) {
        self.route = route
        self.profile = profile
    }
}

public struct DriverEntryResolver: Sendable {
    public init() {}

    public func resolve(session: AuthenticatedSession, profile: DriverProfileDetail?) -> DriverEntryResolution {
        guard session.user.isDriver else {
            return DriverEntryResolution(route: .nonDriver, profile: nil)
        }

        guard let profile else {
            return DriverEntryResolution(route: .missingDriverProfile, profile: nil)
        }

        return DriverEntryResolution(route: .home, profile: profile)
    }
}
