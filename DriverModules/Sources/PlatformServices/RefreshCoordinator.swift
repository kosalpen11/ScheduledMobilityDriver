//
//  RefreshCoordinator.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/4/26.
//

import DriverDomain
import Foundation

public actor RefreshCoordinator {
    public typealias RefreshOperation = @Sendable (_ refreshToken: String, _ idempotencyKey: String, _ triggeringRequestID: String?) async throws -> AuthTokens

    private let storage: any TokenStorage
    private let refresh: RefreshOperation
    private var inFlight: Task<AuthTokens, Error>?

    public init(storage: any TokenStorage, refresh: @escaping RefreshOperation) {
        self.storage = storage
        self.refresh = refresh
    }

    public func validAccessToken() async throws -> String? {
        try await storage.loadTokens()?.accessToken
    }

    public func refreshTokens(triggeringRequestID: String? = nil) async throws -> AuthTokens {
        if let inFlight {
            return try await inFlight.value
        }

        let key = UUID().uuidString
        let storage = storage
        let refresh = refresh
        let task = Task<AuthTokens, Error> {
            guard let existing = try await storage.loadTokens() else {
                throw AuthFailure.invalidRefreshToken
            }
            let tokens = try await refresh(existing.refreshToken, key, triggeringRequestID)
            try await storage.saveTokens(tokens)
            return tokens
        }
        inFlight = task

        do {
            let tokens = try await task.value
            inFlight = nil
            return tokens
        } catch {
            inFlight = nil
            if case AuthFailure.invalidRefreshToken = error {
                await storage.clearTokens()
            }
            throw error
        }
    }

    public func saveTokens(_ tokens: AuthTokens) async throws {
        try await storage.saveTokens(tokens)
    }

    public func clearTokens() async {
        inFlight?.cancel()
        inFlight = nil
        await storage.clearTokens()
    }
}
