//
//  AuthUseCases.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/4/26.
//

import Foundation

public struct RequestOTPUseCase: Sendable {
    private let repository: any AuthRepository

    public init(repository: any AuthRepository) {
        self.repository = repository
    }

    public func callAsFunction(phone: String) async throws -> OTPChallenge {
        let normalized = try PhoneNumberNormalizer.normalizeCambodianPhone(phone)
        return try await repository.requestOTP(phone: normalized)
    }
}

public enum PhoneNumberNormalizer {
    public static func normalizeCambodianPhone(_ phone: String) throws -> String {
        let trimmed = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw AuthFailure.validation("Enter a phone number.")
        }

        let hasPlus = trimmed.hasPrefix("+")
        let digits = trimmed.filter(\.isNumber)
        let local: String
        if hasPlus {
            guard digits.hasPrefix("855") else {
                throw AuthFailure.validation("Use a Cambodia phone number starting with +855.")
            }
            local = String(digits.dropFirst(3))
        } else if digits.hasPrefix("855") {
            local = String(digits.dropFirst(3))
        } else if digits.hasPrefix("0") {
            local = String(digits.dropFirst())
        } else {
            local = digits
        }

        guard (8...9).contains(local.count), local.allSatisfy(\.isNumber) else {
            throw AuthFailure.validation("Enter a valid Cambodia phone number.")
        }
        return "+855\(local)"
    }
}

public struct VerifyOTPUseCase: Sendable {
    private let repository: any AuthRepository

    public init(repository: any AuthRepository) {
        self.repository = repository
    }

    public func callAsFunction(phone: String, code: String, expectedLength: Int) async throws -> AuthenticatedSession {
        let cleanedCode = code.filter(\.isNumber)
        guard cleanedCode.count == expectedLength else {
            throw AuthFailure.validation("Enter the \(expectedLength)-digit code.")
        }
        return try await repository.verifyOTP(phone: phone, code: cleanedCode)
    }
}

public struct RestoreSessionUseCase: Sendable {
    private let repository: any AuthRepository

    public init(repository: any AuthRepository) {
        self.repository = repository
    }

    public func callAsFunction() async throws -> AuthenticatedSession? {
        try await repository.restoreSession()
    }
}

public struct LogoutUseCase: Sendable {
    private let repository: any AuthRepository

    public init(repository: any AuthRepository) {
        self.repository = repository
    }

    public func callAsFunction() async {
        await repository.logout()
    }
}
