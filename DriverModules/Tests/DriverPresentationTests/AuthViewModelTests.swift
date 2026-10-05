//
//  AuthViewModelTests.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/4/26.
//

import DriverDomain
import DriverPresentation
import XCTest

@MainActor
final class AuthViewModelTests: XCTestCase {
    func testDuplicatePhoneSubmissionIsIgnoredWhileRequestIsInFlight() async throws {
        let repository = SlowAuthRepository()
        let model = AuthViewModel(
            requestOTP: RequestOTPUseCase(repository: repository),
            verifyOTP: VerifyOTPUseCase(repository: repository)
        )

        model.submitPhone("012345678")
        model.submitPhone("012345678")

        try await Task.sleep(nanoseconds: 50_000_000)
        let count = await repository.currentRequestCount()
        XCTAssertEqual(count, 1)
    }

    func testStaleVerifyResponseIsIgnoredAfterChangingPhone() async throws {
        let repository = SlowAuthRepository()
        let model = AuthViewModel(
            requestOTP: RequestOTPUseCase(repository: repository),
            verifyOTP: VerifyOTPUseCase(repository: repository)
        )

        model.submitPhone("012345678")
        try await Task.sleep(nanoseconds: 180_000_000)
        model.submitCode("1234") { _ in XCTFail("Stale verification should not authenticate") }
        model.editPhone()
        try await Task.sleep(nanoseconds: 220_000_000)

        guard case .phone(let phone) = model.state else {
            return XCTFail("Expected phone state")
        }
        XCTAssertEqual(phone.phone, "+85512345678")
    }

    func testResendBeforeCooldownShowsMessageWithoutRequest() async throws {
        let repository = SlowAuthRepository()
        let model = AuthViewModel(
            requestOTP: RequestOTPUseCase(repository: repository),
            verifyOTP: VerifyOTPUseCase(repository: repository)
        )

        model.submitPhone("012345678")
        try await Task.sleep(nanoseconds: 180_000_000)
        model.resendCode()

        guard case .code(let code) = model.state else {
            return XCTFail("Expected code state")
        }
        XCTAssertTrue((code.errorMessage ?? "").hasPrefix("Wait "))
        let requestCount = await repository.currentRequestCount()
        XCTAssertEqual(requestCount, 1)
    }
}

private actor SlowAuthRepository: AuthRepository {
    private(set) var requestCount = 0

    func requestOTP(phone: String) async throws -> OTPChallenge {
        requestCount += 1
        try await Task.sleep(nanoseconds: 150_000_000)
        return OTPChallenge(phone: phone, expiresInSeconds: 300, resendAfterSeconds: 60, codeLength: 4)
    }

    func verifyOTP(phone: String, code: String) async throws -> AuthenticatedSession {
        try await Task.sleep(nanoseconds: 150_000_000)
        return AuthenticatedSession(
            user: CurrentUser(
                id: UUID(),
                phone: phone,
                fullName: nil,
                preferredLanguage: "en",
                status: .active,
                roles: []
            ),
            driver: nil
        )
    }

    func restoreSession() async throws -> AuthenticatedSession? {
        nil
    }

    func logout() async {}

    func currentRequestCount() -> Int {
        requestCount
    }
}
