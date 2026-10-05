//
//  AuthUseCaseTests.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/4/26.
//

import DriverDomain
import XCTest

final class AuthUseCaseTests: XCTestCase {
    func testRestoreSessionReturnsExistingSession() async throws {
        let session = AuthenticatedSession(
            user: CurrentUser(
                id: UUID(),
                phone: "+85512345678",
                fullName: "Driver",
                preferredLanguage: "en",
                status: .active,
                roles: [RoleGrant(role: .driver, scopeID: nil)]
            ),
            driver: nil
        )
        let repository = StubAuthRepository(session: session)
        let restored = try await RestoreSessionUseCase(repository: repository)()
        XCTAssertEqual(restored, session)
    }

    func testVerifyOTPRejectsWrongLengthBeforeRepositoryCall() async {
        let repository = StubAuthRepository(session: nil)
        let useCase = VerifyOTPUseCase(repository: repository)

        do {
            _ = try await useCase(phone: "+85512345678", code: "12", expectedLength: 4)
            XCTFail("Expected validation error")
        } catch AuthFailure.validation {
            let count = await repository.verifyCallCount
            XCTAssertEqual(count, 0)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRequestOTPNormalizesCambodianLocalPhone() async throws {
        let repository = StubAuthRepository(session: nil)
        let challenge = try await RequestOTPUseCase(repository: repository)(phone: "012 345 678")
        let requestedPhone = await repository.currentRequestedPhone()
        XCTAssertEqual(challenge.phone, "+85512345678")
        XCTAssertEqual(requestedPhone, "+85512345678")
    }

    func testRequestOTPRejectsNonCambodianPhone() async {
        let repository = StubAuthRepository(session: nil)
        do {
            _ = try await RequestOTPUseCase(repository: repository)(phone: "+1 555 123 4567")
            XCTFail("Expected validation")
        } catch AuthFailure.validation(let message) {
            XCTAssertEqual(message, "Use a Cambodia phone number starting with +855.")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private actor StubAuthRepository: AuthRepository {
    private let session: AuthenticatedSession?
    private(set) var verifyCallCount = 0
    private(set) var requestedPhone: String?

    init(session: AuthenticatedSession?) {
        self.session = session
    }

    func requestOTP(phone: String) async throws -> OTPChallenge {
        requestedPhone = phone
        return OTPChallenge(phone: phone, expiresInSeconds: 300, resendAfterSeconds: 60, codeLength: 4)
    }

    func verifyOTP(phone: String, code: String) async throws -> AuthenticatedSession {
        verifyCallCount += 1
        return session!
    }

    func restoreSession() async throws -> AuthenticatedSession? {
        session
    }

    func logout() async {}

    func currentRequestedPhone() -> String? {
        requestedPhone
    }
}
