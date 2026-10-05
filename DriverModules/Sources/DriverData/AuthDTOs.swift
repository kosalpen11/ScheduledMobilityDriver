//
//  AuthDTOs.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/4/26.
//

import DriverDomain
import Foundation
import PlatformServices

struct OtpRequestDTO: Encodable {
    let phone: String
}

struct OtpRequestedDTO: Decodable {
    let expiresInSeconds: Int
    let resendAfterSeconds: Int
}

struct OtpVerifyDTO: Encodable {
    let phone: String
    let code: String
}

struct RefreshRequestDTO: Encodable {
    let refreshToken: String
}

struct TokenResponseDTO: Decodable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int
    let refreshToken: String
    let refreshExpiresIn: Int

    func domain() -> AuthTokens {
        AuthTokens(
            accessToken: accessToken,
            tokenType: tokenType,
            expiresInSeconds: expiresIn,
            refreshToken: refreshToken,
            refreshExpiresInSeconds: refreshExpiresIn
        )
    }
}

struct MeDTO: Decodable {
    let id: UUID
    let phone: String
    let fullName: String?
    let preferredLang: String
    let status: String
    let roles: [RoleGrantDTO]

    func domain() -> CurrentUser {
        CurrentUser(
            id: id,
            phone: phone,
            fullName: fullName,
            preferredLanguage: preferredLang,
            status: AccountStatus(rawValue: status) ?? .unknown,
            roles: roles.map { $0.domain() }
        )
    }
}

struct RoleGrantDTO: Decodable {
    let role: String
    let scopeId: UUID?

    func domain() -> RoleGrant {
        RoleGrant(role: UserRole(rawValue: role) ?? .unknown, scopeID: scopeId)
    }
}

struct DriverDetailDTO: Decodable {
    let id: UUID
    let userId: UUID
    let phone: String
    let fullName: String
    let status: String

    func domain() -> DriverIdentity {
        DriverIdentity(
            id: id,
            userID: userId,
            phone: phone,
            fullName: fullName,
            approvalStatus: approvalStatus
        )
    }

    private var approvalStatus: DriverApprovalStatus {
        switch status {
        case "APPROVED":
            return .approved
        case "REJECTED":
            return .rejected(reason: nil)
        default:
            return .pendingReview
        }
    }
}

enum AuthErrorMapper {
    static func map(_ error: Error) -> Error {
        guard let http = error as? HTTPClientError else {
            return error
        }

        switch http {
        case .badStatus(let status, let problem):
            let message = problem?.detail ?? problem?.title ?? "Request failed."
            switch (status, problem?.code) {
            case (400, "otp.invalid"):
                return AuthFailure.invalidOTP(message)
            case (400, "phone.invalid"):
                return AuthFailure.validation(message)
            case (401, "refresh-token.invalid"):
                return AuthFailure.invalidRefreshToken
            case (401, _):
                return AuthFailure.unauthorized
            case (403, "account.inactive"):
                return AuthFailure.inactiveAccount(message)
            case (403, _):
                return AuthFailure.forbidden
            case (429, _):
                return AuthFailure.rateLimited(retryAfterSeconds: nil, message: message)
            default:
                return AuthFailure.server(message)
            }
        case .transport(let message):
            return AuthFailure.transient(message)
        case .decoding, .invalidResponse:
            return AuthFailure.server("The server response could not be read.")
        }
    }
}
