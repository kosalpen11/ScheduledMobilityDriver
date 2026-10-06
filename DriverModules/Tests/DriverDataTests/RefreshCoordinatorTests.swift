//
//  RefreshCoordinatorTests.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/4/26.
//

import DriverDomain
import PlatformServices
import XCTest

final class RefreshCoordinatorTests: XCTestCase {
    func testConcurrentRefreshSharesOneInFlightOperation() async throws {
        let storage = InMemoryTokenStorage(tokens: oldTokens)
        let counter = RefreshCounter()
        let coordinator = RefreshCoordinator(storage: storage) { _, _, _ in
            await counter.increment()
            try await Task.sleep(nanoseconds: 100_000_000)
            return self.newTokens
        }

        async let first = coordinator.refreshTokens()
        async let second = coordinator.refreshTokens()

        let results = try await [first, second]
        XCTAssertEqual(results, [newTokens, newTokens])
        let refreshCount = await counter.value
        let storedTokens = try await storage.loadTokens()
        XCTAssertEqual(refreshCount, 1)
        XCTAssertEqual(storedTokens, newTokens)
    }

    func testInvalidRefreshClearsStoredTokens() async throws {
        let storage = InMemoryTokenStorage(tokens: oldTokens)
        let coordinator = RefreshCoordinator(storage: storage) { _, _, _ in
            throw AuthFailure.invalidRefreshToken
        }

        do {
            _ = try await coordinator.refreshTokens()
            XCTFail("Expected refresh to fail")
        } catch AuthFailure.invalidRefreshToken {
            let storedTokens = try await storage.loadTokens()
            XCTAssertNil(storedTokens)
        }
    }

    func testTransientRefreshFailurePreservesStoredTokens() async throws {
        let storage = InMemoryTokenStorage(tokens: oldTokens)
        let coordinator = RefreshCoordinator(storage: storage) { _, _, _ in
            throw AuthFailure.transient("offline")
        }

        do {
            _ = try await coordinator.refreshTokens()
            XCTFail("Expected refresh to fail")
        } catch AuthFailure.transient {
            let storedTokens = try await storage.loadTokens()
            XCTAssertEqual(storedTokens, oldTokens)
        }
    }

    private var oldTokens: AuthTokens {
        AuthTokens(
            accessToken: "old-access",
            tokenType: "Bearer",
            expiresInSeconds: 900,
            refreshToken: "old-refresh",
            refreshExpiresInSeconds: 2_592_000
        )
    }

    private var newTokens: AuthTokens {
        AuthTokens(
            accessToken: "new-access",
            tokenType: "Bearer",
            expiresInSeconds: 900,
            refreshToken: "new-refresh",
            refreshExpiresInSeconds: 2_592_000
        )
    }
}

private actor RefreshCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}
