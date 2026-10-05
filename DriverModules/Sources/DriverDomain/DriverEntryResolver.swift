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
    private let eligibility = DriverEligibilityPolicy()

    public init() {}

    public func resolve(session: AuthenticatedSession, profile: DriverProfileDetail?) -> DriverEntryResolution {
        guard session.user.isDriver else {
            return DriverEntryResolution(route: .nonDriver, profile: nil)
        }

        guard let profile else {
            return DriverEntryResolution(route: .missingDriverProfile, profile: nil)
        }

        switch profile.status {
        case .pending:
            return DriverEntryResolution(route: .onboarding, profile: profile)
        case .documentsSubmitted:
            return DriverEntryResolution(route: .applicationReview, profile: profile)
        case .training:
            return DriverEntryResolution(route: .training, profile: profile)
        case .rejected:
            return DriverEntryResolution(route: .rejected, profile: profile)
        case .suspended:
            return DriverEntryResolution(route: .suspended, profile: profile)
        case .approved:
            return DriverEntryResolution(route: eligibility.canOperate(profile) ? .home : .readiness, profile: profile)
        case .unknown:
            return DriverEntryResolution(route: .readiness, profile: profile)
        }
    }
}
