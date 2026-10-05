//
//  AuthAPIRepository.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/4/26.
//

import DriverDomain
import Foundation
import PlatformServices

public final class AuthAPIRepository: AuthRepository, AuthTokenRepository, @unchecked Sendable {
    private let client: HTTPClient
    private let tokenStorage: any TokenStorage
    private let refreshCoordinator: RefreshCoordinator
    private let otpCodeLength: Int

    public init(
        client: HTTPClient,
        tokenStorage: any TokenStorage,
        otpCodeLength: Int = 4
    ) {
        self.client = client
        self.tokenStorage = tokenStorage
        self.otpCodeLength = otpCodeLength
        self.refreshCoordinator = RefreshCoordinator(storage: tokenStorage) { refreshToken, key, triggeringRequestID in
            do {
                let context = HTTPRequestContext(linkedRequestID: triggeringRequestID)
                let response: TokenResponseDTO = try await client.send(
                    "POST",
                    path: "auth/refresh",
                    body: RefreshRequestDTO(refreshToken: refreshToken),
                    headers: ["Idempotency-Key": key],
                    context: context
                )
                return response.domain()
            } catch {
                throw AuthErrorMapper.map(error)
            }
        }
    }

    public func requestOTP(phone: String) async throws -> OTPChallenge {
        do {
            let key = UUID().uuidString
            let context = HTTPRequestContext()
            let response: OtpRequestedDTO = try await client.send(
                "POST",
                path: "auth/otp/request",
                body: OtpRequestDTO(phone: phone),
                headers: ["Idempotency-Key": key],
                context: context
            )
            return OTPChallenge(
                phone: phone,
                expiresInSeconds: response.expiresInSeconds,
                resendAfterSeconds: response.resendAfterSeconds,
                codeLength: otpCodeLength
            )
        } catch {
            throw AuthErrorMapper.map(error)
        }
    }

    public func verifyOTP(phone: String, code: String) async throws -> AuthenticatedSession {
        do {
            let context = HTTPRequestContext()
            let response: TokenResponseDTO = try await client.send(
                "POST",
                path: "auth/otp/verify",
                body: OtpVerifyDTO(phone: phone, code: code),
                headers: ["Idempotency-Key": UUID().uuidString],
                context: context
            )
            try await refreshCoordinator.saveTokens(response.domain())
            return try await loadSession()
        } catch {
            throw AuthErrorMapper.map(error)
        }
    }

    public func restoreSession() async throws -> AuthenticatedSession? {
        guard try await tokenStorage.loadTokens() != nil else {
            return nil
        }

        do {
            return try await loadSession()
        } catch AuthFailure.unauthorized {
            do {
                _ = try await refreshCoordinator.refreshTokens()
                return try await loadSession()
            } catch AuthFailure.invalidRefreshToken {
                await tokenStorage.clearTokens()
                return nil
            }
        } catch AuthFailure.invalidRefreshToken {
            await tokenStorage.clearTokens()
            return nil
        } catch {
            throw error
        }
    }

    public func refreshTokens() async throws -> AuthTokens {
        do {
            return try await refreshCoordinator.refreshTokens()
        } catch {
            throw AuthErrorMapper.map(error)
        }
    }

    public func authenticatedSend<Response: Decodable, Body: Encodable>(
        _ method: String,
        path: String,
        body: Body?,
        headers: [String: String] = [:]
    ) async throws -> Response {
        let context = HTTPRequestContext()
        guard let access = try await refreshCoordinator.validAccessToken() else {
            throw AuthFailure.unauthorized
        }

        do {
            return try await client.send(method, path: path, body: body, headers: headers, authenticatedBy: access, context: context)
        } catch HTTPClientError.badStatus(401, _) {
            let tokens = try await refreshCoordinator.refreshTokens(triggeringRequestID: context.requestID)
            return try await client.send(
                method,
                path: path,
                body: body,
                headers: headers,
                authenticatedBy: tokens.accessToken,
                context: context.retryAttempt(2)
            )
        } catch {
            throw AuthErrorMapper.map(error)
        }
    }

    public func authenticatedMultipartSend<Response: Decodable>(
        _ method: String,
        path: String,
        parts: [MultipartFormPart],
        headers: [String: String] = [:]
    ) async throws -> Response {
        let context = HTTPRequestContext()
        guard let access = try await refreshCoordinator.validAccessToken() else {
            throw AuthFailure.unauthorized
        }

        do {
            return try await client.sendMultipart(method, path: path, parts: parts, headers: headers, authenticatedBy: access, context: context)
        } catch HTTPClientError.badStatus(401, _) {
            let tokens = try await refreshCoordinator.refreshTokens(triggeringRequestID: context.requestID)
            return try await client.sendMultipart(
                method,
                path: path,
                parts: parts,
                headers: headers,
                authenticatedBy: tokens.accessToken,
                context: context.retryAttempt(2)
            )
        } catch {
            throw AuthErrorMapper.map(error)
        }
    }

    public func logout() async {
        if let tokens = try? await tokenStorage.loadTokens() {
            try? await client.sendEmpty(
                "POST",
                path: "auth/logout",
                body: RefreshRequestDTO(refreshToken: tokens.refreshToken),
                headers: ["Idempotency-Key": UUID().uuidString],
                authenticatedBy: tokens.accessToken,
                context: HTTPRequestContext()
            )
        }
        await refreshCoordinator.clearTokens()
    }

    private func loadSession() async throws -> AuthenticatedSession {
        do {
            let me: MeDTO = try await authenticatedSend("GET", path: "me", body: Optional<EmptyBody>.none)
            return AuthenticatedSession(user: me.domain(), driver: nil)
        } catch {
            throw AuthErrorMapper.map(error)
        }
    }
}
