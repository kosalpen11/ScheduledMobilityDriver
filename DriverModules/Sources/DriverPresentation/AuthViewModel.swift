//
//  AuthViewModel.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/4/26.
//

import Combine
import DriverDomain
import Foundation

@MainActor
public final class AuthViewModel: ObservableObject {
    @Published public private(set) var state: AuthViewState

    private let requestOTP: RequestOTPUseCase
    private let verifyOTP: VerifyOTPUseCase
    private var task: Task<Void, Never>?
    private var flowID = UUID()

    public init(requestOTP: RequestOTPUseCase, verifyOTP: VerifyOTPUseCase) {
        self.requestOTP = requestOTP
        self.verifyOTP = verifyOTP
        self.state = .phone(AuthPhoneState(phone: "+855"))
    }

    deinit {
        task?.cancel()
    }

    public func submitPhone(_ phone: String) {
        guard state.isSubmitting == false else { return }
        state = .phone(AuthPhoneState(phone: phone, isSubmitting: true))
        let requestID = UUID()
        flowID = requestID

        task = Task { [weak self] in
            guard let self else { return }
            do {
                let challenge = try await requestOTP(phone: phone)
                guard flowID == requestID else { return }
                state = .code(AuthCodeState(challenge: challenge))
            } catch {
                guard flowID == requestID else { return }
                state = .phone(AuthPhoneState(phone: phone, errorMessage: Self.message(for: error)))
            }
        }
    }

    public func submitCode(_ code: String, onAuthenticated: @escaping (AuthenticatedSession) -> Void) {
        guard state.isSubmitting == false, case .code(let current) = state else { return }

        let normalized = code.filter(\.isNumber)
        state = .code(current.submitting(code: normalized))
        let requestID = flowID

        task = Task { [weak self] in
            guard let self else { return }
            do {
                let session = try await verifyOTP(
                    phone: current.challenge.phone,
                    code: normalized,
                    expectedLength: current.challenge.codeLength
                )
                guard flowID == requestID else { return }
                state = .authenticated(session)
                onAuthenticated(session)
            } catch {
                guard flowID == requestID else { return }
                state = .code(current.failed(code: normalized, message: Self.message(for: error)))
            }
        }
    }

    public func resendCode() {
        guard state.isSubmitting == false, case .code(let current) = state else { return }
        guard current.canResend else {
            state = .code(current.failed(code: current.code, message: "Wait \(current.resendRemainingSeconds) seconds before requesting another code."))
            return
        }
        submitPhone(current.challenge.phone)
    }

    public func editPhone() {
        guard case .code(let codeState) = state else { return }
        flowID = UUID()
        task?.cancel()
        state = .phone(AuthPhoneState(phone: codeState.challenge.phone))
    }

    private static func message(for error: Error) -> String {
        switch error {
        case AuthFailure.validation(let message),
             AuthFailure.invalidOTP(let message),
             AuthFailure.inactiveAccount(let message),
             AuthFailure.server(let message),
             AuthFailure.transient(let message):
            return message
        case AuthFailure.rateLimited(_, let message):
            return message
        case AuthFailure.invalidRefreshToken:
            return "Your session expired. Sign in again."
        case AuthFailure.unauthorized:
            return "Sign in again to continue."
        case AuthFailure.forbidden:
            return "This account is not allowed to use the driver app."
        default:
            return "Something went wrong. Try again."
        }
    }
}

public enum AuthViewState: Equatable {
    case phone(AuthPhoneState)
    case code(AuthCodeState)
    case authenticated(AuthenticatedSession)

    public var isSubmitting: Bool {
        switch self {
        case .phone(let state):
            return state.isSubmitting
        case .code(let state):
            return state.isSubmitting
        case .authenticated:
            return false
        }
    }
}

public struct AuthPhoneState: Equatable {
    public let phone: String
    public let isSubmitting: Bool
    public let errorMessage: String?

    public init(phone: String = "", isSubmitting: Bool = false, errorMessage: String? = nil) {
        self.phone = phone
        self.isSubmitting = isSubmitting
        self.errorMessage = errorMessage
    }
}

public struct AuthCodeState: Equatable {
    public let challenge: OTPChallenge
    public let code: String
    public let isSubmitting: Bool
    public let errorMessage: String?
    public let resendAvailableAt: Date

    public init(
        challenge: OTPChallenge,
        code: String = "",
        isSubmitting: Bool = false,
        errorMessage: String? = nil,
        resendAvailableAt: Date? = nil
    ) {
        self.challenge = challenge
        self.code = code
        self.isSubmitting = isSubmitting
        self.errorMessage = errorMessage
        self.resendAvailableAt = resendAvailableAt ?? Date().addingTimeInterval(TimeInterval(challenge.resendAfterSeconds))
    }

    func submitting(code: String) -> AuthCodeState {
        AuthCodeState(challenge: challenge, code: code, isSubmitting: true, errorMessage: nil, resendAvailableAt: resendAvailableAt)
    }

    func failed(code: String, message: String) -> AuthCodeState {
        AuthCodeState(challenge: challenge, code: code, isSubmitting: false, errorMessage: message, resendAvailableAt: resendAvailableAt)
    }

    public var canResend: Bool {
        resendRemainingSeconds == 0
    }

    public var resendRemainingSeconds: Int {
        max(0, Int(ceil(resendAvailableAt.timeIntervalSinceNow)))
    }
}
