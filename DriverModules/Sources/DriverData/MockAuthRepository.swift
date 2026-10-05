//
//  MockAuthRepository.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/4/26.
//

import DriverDomain
import Foundation

public actor MockAuthRepository: AuthRepository {
    private var session: AuthenticatedSession?
    private let acceptedCode: String

    public init(
        acceptedCode: String = "1234",
        initialSession: AuthenticatedSession? = nil
    ) {
        self.acceptedCode = acceptedCode
        self.session = initialSession
    }

    public func requestOTP(phone: String) async throws -> OTPChallenge {
        OTPChallenge(phone: phone, expiresInSeconds: 300, resendAfterSeconds: 60, codeLength: acceptedCode.count)
    }

    public func verifyOTP(phone: String, code: String) async throws -> AuthenticatedSession {
        guard code == acceptedCode else {
            throw AuthFailure.invalidOTP("The code did not match. Try again.")
        }

        let user = CurrentUser(
            id: UUID(uuidString: "86F78676-5FDB-4245-B7E8-69EBA01D961E")!,
            phone: phone,
            fullName: "Mock Driver",
            preferredLanguage: "en",
            status: .active,
            roles: [RoleGrant(role: .driver, scopeID: nil)]
        )
        let driver = DriverIdentity(
            id: UUID(uuidString: "BE6FCA86-EBF4-401F-B9BF-A1A6336139A6")!,
            userID: user.id,
            phone: phone,
            fullName: "Mock Driver",
            approvalStatus: .approved
        )
        let session = AuthenticatedSession(user: user, driver: driver)
        self.session = session
        return session
    }

    public func restoreSession() async throws -> AuthenticatedSession? {
        session
    }

    public func logout() async {
        session = nil
    }
}
