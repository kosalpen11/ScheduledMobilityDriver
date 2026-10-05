//
//  AuthModels.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/4/26.
//

import Foundation

public struct OTPChallenge: Equatable, Sendable {
    public let phone: String
    public let expiresInSeconds: Int
    public let resendAfterSeconds: Int
    public let codeLength: Int

    public init(phone: String, expiresInSeconds: Int, resendAfterSeconds: Int, codeLength: Int) {
        self.phone = phone
        self.expiresInSeconds = expiresInSeconds
        self.resendAfterSeconds = resendAfterSeconds
        self.codeLength = codeLength
    }
}

public struct AuthTokens: Codable, Equatable, Sendable {
    public let accessToken: String
    public let tokenType: String
    public let expiresInSeconds: Int
    public let refreshToken: String
    public let refreshExpiresInSeconds: Int

    public init(
        accessToken: String,
        tokenType: String,
        expiresInSeconds: Int,
        refreshToken: String,
        refreshExpiresInSeconds: Int
    ) {
        self.accessToken = accessToken
        self.tokenType = tokenType
        self.expiresInSeconds = expiresInSeconds
        self.refreshToken = refreshToken
        self.refreshExpiresInSeconds = refreshExpiresInSeconds
    }
}

public struct CurrentUser: Equatable, Sendable {
    public let id: UUID
    public let phone: String
    public let fullName: String?
    public let preferredLanguage: String
    public let status: AccountStatus
    public let roles: [RoleGrant]

    public init(
        id: UUID,
        phone: String,
        fullName: String?,
        preferredLanguage: String,
        status: AccountStatus,
        roles: [RoleGrant]
    ) {
        self.id = id
        self.phone = phone
        self.fullName = fullName
        self.preferredLanguage = preferredLanguage
        self.status = status
        self.roles = roles
    }

    public var isDriver: Bool {
        roles.contains { $0.role == .driver }
    }
}

public struct RoleGrant: Equatable, Sendable {
    public let role: UserRole
    public let scopeID: UUID?

    public init(role: UserRole, scopeID: UUID?) {
        self.role = role
        self.scopeID = scopeID
    }
}

public enum UserRole: String, Equatable, Sendable {
    case passenger = "PASSENGER"
    case driver = "DRIVER"
    case admin = "ADMIN"
    case dispatcher = "DISPATCHER"
    case support = "SUPPORT"
    case safetyOfficer = "SAFETY_OFFICER"
    case unknown
}

public enum AccountStatus: String, Equatable, Sendable {
    case active = "ACTIVE"
    case suspended = "SUSPENDED"
    case disabled = "DISABLED"
    case unknown
}

public struct DriverIdentity: Equatable, Sendable {
    public let id: UUID
    public let userID: UUID
    public let phone: String
    public let fullName: String
    public let approvalStatus: DriverApprovalStatus

    public init(
        id: UUID,
        userID: UUID,
        phone: String,
        fullName: String,
        approvalStatus: DriverApprovalStatus
    ) {
        self.id = id
        self.userID = userID
        self.phone = phone
        self.fullName = fullName
        self.approvalStatus = approvalStatus
    }
}

public struct AuthenticatedSession: Equatable, Sendable {
    public let user: CurrentUser
    public let driver: DriverIdentity?

    public init(user: CurrentUser, driver: DriverIdentity?) {
        self.user = user
        self.driver = driver
    }
}

public enum AuthFailure: Error, Equatable, Sendable {
    case validation(String)
    case invalidOTP(String)
    case rateLimited(retryAfterSeconds: Int?, message: String)
    case inactiveAccount(String)
    case invalidRefreshToken
    case unauthorized
    case forbidden
    case transient(String)
    case server(String)
}
