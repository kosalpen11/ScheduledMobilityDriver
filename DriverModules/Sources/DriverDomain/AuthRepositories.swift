//
//  AuthRepositories.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/4/26.
//

import Foundation

public protocol AuthRepository: Sendable {
    func requestOTP(phone: String) async throws -> OTPChallenge
    func verifyOTP(phone: String, code: String) async throws -> AuthenticatedSession
    func restoreSession() async throws -> AuthenticatedSession?
    func logout() async
}

public protocol AuthTokenRepository: Sendable {
    func refreshTokens() async throws -> AuthTokens
}
