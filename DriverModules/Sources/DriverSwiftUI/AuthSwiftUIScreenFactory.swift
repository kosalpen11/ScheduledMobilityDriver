//
//  AuthSwiftUIScreenFactory.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/5/26.
//

import DesignSystem
import DriverDomain
import DriverPresentation
import FeatureContracts
import SwiftUI
import UIKit

public final class AuthSwiftUIScreenFactory: AuthScreenFactory {
    private let requestOTP: RequestOTPUseCase
    private let verifyOTP: VerifyOTPUseCase
    private let allowsDevelopmentBypass: Bool

    public init(
        requestOTP: RequestOTPUseCase,
        verifyOTP: VerifyOTPUseCase,
        allowsDevelopmentBypass: Bool = false
    ) {
        self.requestOTP = requestOTP
        self.verifyOTP = verifyOTP
        self.allowsDevelopmentBypass = allowsDevelopmentBypass
    }

    public func makeAuth(onOutput: @escaping (AuthOutput) -> Void) -> UIViewController {
        let model = AuthViewModel(requestOTP: requestOTP, verifyOTP: verifyOTP)
        let view = AuthFlowView(
            model: model,
            allowsDevelopmentBypass: allowsDevelopmentBypass,
            onOutput: onOutput
        )
        return UIHostingController(rootView: view)
    }
}

private struct AuthFlowView: View {
    @ObservedObject var model: AuthViewModel
    let allowsDevelopmentBypass: Bool
    let onOutput: (AuthOutput) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color(DriverTheme.panelColor)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 28) {
                Spacer(minLength: 18)
                brandHeader

                Group {
                    switch model.state {
                    case .phone(let state):
                        PhoneLoginView(
                            state: state,
                            allowsDevelopmentBypass: allowsDevelopmentBypass,
                            onSubmit: { phone in
                                impact()
                                model.submitPhone(phone)
                            },
                            onBypass: {
                                impact()
                                onOutput(.developmentHomeBypass)
                            }
                        )
                    case .code(let state):
                        OTPVerificationView(
                            state: state,
                            onSubmit: { code in
                                impact()
                                model.submitCode(code) { session in
                                    onOutput(.authenticated(session))
                                }
                            },
                            onChangeNumber: {
                                impact()
                                model.editPhone()
                            },
                            onResend: {
                                impact()
                                model.resendCode()
                            }
                        )
                    case .authenticated:
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 180)
                    }
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: model.state)

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
        }
        .navigationBarHidden(true)
    }

    private var brandHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Scheduled Mobility")
                .font(.largeTitle.weight(.bold))
                .foregroundColor(.primary)
                .minimumScaleFactor(0.82)
            Text("Driver")
                .font(.title2.weight(.semibold))
                .foregroundColor(Color(DriverTheme.brandColor))
        }
        .accessibilityElement(children: .combine)
    }

    private func impact() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

private struct PhoneLoginView: View {
    let state: AuthPhoneState
    let allowsDevelopmentBypass: Bool
    let onSubmit: (String) -> Void
    let onBypass: () -> Void
    @State private var phone: String
    @FocusState private var isFocused: Bool

    init(
        state: AuthPhoneState,
        allowsDevelopmentBypass: Bool,
        onSubmit: @escaping (String) -> Void,
        onBypass: @escaping () -> Void
    ) {
        self.state = state
        self.allowsDevelopmentBypass = allowsDevelopmentBypass
        self.onSubmit = onSubmit
        self.onBypass = onBypass
        self._phone = State(initialValue: state.phone.isEmpty ? "+855" : state.phone)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Sign in with your phone")
                    .font(.title.weight(.bold))
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Use your Cambodia phone number. We will send a secure four-digit code.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Phone number")
                    .font(.headline)
                TextField("+855 12 345 678", text: $phone)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .focused($isFocused)
                    .font(.title3.weight(.semibold))
                    .padding(.horizontal, 14)
                    .frame(minHeight: DriverTheme.controlHeight)
                    .background(Color(DriverTheme.cardColor))
                    .clipShape(RoundedRectangle(cornerRadius: DriverTheme.cardCornerRadius, style: .continuous))
                    .accessibilityLabel("Cambodia phone number")
            }

            if let message = state.errorMessage {
                Text(message)
                    .font(.callout.weight(.semibold))
                    .foregroundColor(Color(DriverTheme.destructiveColor))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                onSubmit(phone)
            } label: {
                HStack {
                    if state.isSubmitting {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(state.isSubmitting ? "Sending" : "Continue")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, minHeight: DriverTheme.controlHeight)
            }
            .buttonStyle(PrimaryDriverButtonStyle())
            .disabled(state.isSubmitting)
            .accessibilityHint("Requests a one-time code from the staging driver API.")

            if allowsDevelopmentBypass {
                Button("Skip sign in (Development)", action: onBypass)
                    .font(.callout.weight(.semibold))
                    .foregroundColor(Color(DriverTheme.brandColor))
                    .frame(maxWidth: .infinity, minHeight: DriverTheme.minimumTouchTarget)
                    .accessibilityHint("Opens Home without a signed-in staging account. Development use only.")
            }
        }
        .onAppear {
            isFocused = true
        }
        .onChange(of: state.phone) { value in
            guard state.isSubmitting == false else { return }
            phone = value
        }
    }
}

private struct OTPVerificationView: View {
    let state: AuthCodeState
    let onSubmit: (String) -> Void
    let onChangeNumber: () -> Void
    let onResend: () -> Void
    @State private var code: String
    @FocusState private var isFocused: Bool

    init(
        state: AuthCodeState,
        onSubmit: @escaping (String) -> Void,
        onChangeNumber: @escaping () -> Void,
        onResend: @escaping () -> Void
    ) {
        self.state = state
        self.onSubmit = onSubmit
        self.onChangeNumber = onChangeNumber
        self.onResend = onResend
        self._code = State(initialValue: state.code)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Enter the code")
                    .font(.title.weight(.bold))
                Text("We sent a four-digit code to \(state.challenge.phone).")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ZStack {
                TextField("", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .focused($isFocused)
                    .opacity(0.02)
                    .frame(width: 1, height: 1)
                    .accessibilityLabel("One-time code")
                    .onChange(of: code) { newValue in
                        code = String(newValue.filter(\.isNumber).prefix(state.challenge.codeLength))
                    }

                HStack(spacing: 12) {
                    ForEach(0..<state.challenge.codeLength, id: \.self) { index in
                        Text(character(at: index))
                            .font(.title.weight(.bold))
                            .frame(maxWidth: .infinity, minHeight: 62)
                            .background(Color(DriverTheme.cardColor))
                            .clipShape(RoundedRectangle(cornerRadius: DriverTheme.cardCornerRadius, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: DriverTheme.cardCornerRadius, style: .continuous)
                                    .stroke(index == code.count ? Color(DriverTheme.brandColor) : Color.clear, lineWidth: 2)
                            )
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    isFocused = true
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("One-time code")
                .accessibilityValue(code.isEmpty ? "Empty" : code)
            }

            HStack {
                Button("Change number", action: onChangeNumber)
                Spacer()
                Button(resendTitle, action: onResend)
                    .disabled(state.isSubmitting)
            }
            .font(.callout.weight(.semibold))
            .foregroundColor(Color(DriverTheme.brandColor))
            .frame(minHeight: DriverTheme.minimumTouchTarget)

            if let message = state.errorMessage {
                Text(message)
                    .font(.callout.weight(.semibold))
                    .foregroundColor(Color(DriverTheme.destructiveColor))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                onSubmit(code)
            } label: {
                HStack {
                    if state.isSubmitting {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(state.isSubmitting ? "Verifying" : "Verify")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, minHeight: DriverTheme.controlHeight)
            }
            .buttonStyle(PrimaryDriverButtonStyle())
            .disabled(state.isSubmitting || code.count != state.challenge.codeLength)
        }
        .onAppear {
            isFocused = true
        }
        .onChange(of: state.code) { value in
            code = value
        }
    }

    private var resendTitle: String {
        state.canResend ? "Resend code" : "Resend in \(state.resendRemainingSeconds)s"
    }

    private func character(at index: Int) -> String {
        guard index < code.count else { return "" }
        let stringIndex = code.index(code.startIndex, offsetBy: index)
        return String(code[stringIndex])
    }
}

private struct PrimaryDriverButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.white)
            .background(
                RoundedRectangle(cornerRadius: DriverTheme.cardCornerRadius, style: .continuous)
                    .fill(Color(DriverTheme.brandColor))
            )
            .opacity(configuration.isPressed ? 0.84 : 1)
    }
}
