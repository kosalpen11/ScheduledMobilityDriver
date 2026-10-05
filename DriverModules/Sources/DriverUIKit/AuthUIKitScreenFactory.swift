//
//  AuthUIKitScreenFactory.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/4/26.
//

import DriverDomain
import DriverPresentation
import FeatureContracts
import UIKit

public final class AuthUIKitScreenFactory: AuthScreenFactory {
    private let requestOTP: RequestOTPUseCase
    private let verifyOTP: VerifyOTPUseCase

    public init(requestOTP: RequestOTPUseCase, verifyOTP: VerifyOTPUseCase) {
        self.requestOTP = requestOTP
        self.verifyOTP = verifyOTP
    }

    public func makeAuth(onOutput: @escaping (AuthOutput) -> Void) -> UIViewController {
        let model = AuthViewModel(requestOTP: requestOTP, verifyOTP: verifyOTP)
        return AuthViewController(model: model, onOutput: onOutput)
    }
}
