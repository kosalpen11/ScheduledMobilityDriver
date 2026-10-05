//
//  TokenStorage.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/4/26.
//

import DriverDomain
import Foundation
import Security

public protocol TokenStorage: Sendable {
    func loadTokens() async throws -> AuthTokens?
    func saveTokens(_ tokens: AuthTokens) async throws
    func clearTokens() async
}

public actor InMemoryTokenStorage: TokenStorage {
    private var tokens: AuthTokens?

    public init(tokens: AuthTokens? = nil) {
        self.tokens = tokens
    }

    public func loadTokens() async throws -> AuthTokens? {
        tokens
    }

    public func saveTokens(_ tokens: AuthTokens) async throws {
        self.tokens = tokens
    }

    public func clearTokens() async {
        tokens = nil
    }
}

public final class KeychainTokenStorage: TokenStorage {
    private let service: String
    private let account: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(service: String = Bundle.main.bundleIdentifier ?? "com.scheduledmobility.driver", account: String = "auth.tokens") {
        self.service = service
        self.account = account
    }

    public func loadTokens() async throws -> AuthTokens? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = item as? Data else {
            throw KeychainError.unhandled(status)
        }
        return try decoder.decode(AuthTokens.self, from: data)
    }

    public func saveTokens(_ tokens: AuthTokens) async throws {
        let data = try encoder.encode(tokens)
        var query = baseQuery()
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updateStatus = SecItemUpdate(baseQuery() as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw KeychainError.unhandled(updateStatus)
            }
        } else if status != errSecSuccess {
            throw KeychainError.unhandled(status)
        }
    }

    public func clearTokens() async {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

public enum KeychainError: Error, Equatable {
    case unhandled(OSStatus)
}
