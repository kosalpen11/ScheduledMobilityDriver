//
//  AuthViewController.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/4/26.
//

import Combine
import DesignSystem
import DriverDomain
import DriverPresentation
import FeatureContracts
import UIKit

final class AuthViewController: UIViewController {
    private let model: AuthViewModel
    private let onOutput: (AuthOutput) -> Void
    private var cancellables = Set<AnyCancellable>()
    private var currentChallenge: OTPChallenge?
    private var resendTimer: Timer?

    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let textField = UITextField()
    private let primaryButton = UIButton(type: .system)
    private let secondaryButton = UIButton(type: .system)
    private let errorLabel = UILabel()

    init(model: AuthViewModel, onOutput: @escaping (AuthOutput) -> Void) {
        self.model = model
        self.onOutput = onOutput
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Sign In"
        view.backgroundColor = .systemBackground
        configureLayout()
        bind()
    }

    deinit {
        stopResendTimer()
    }

    private func configureLayout() {
        titleLabel.font = .preferredFont(forTextStyle: .largeTitle)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 0

        subtitleLabel.font = .preferredFont(forTextStyle: .body)
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 0

        textField.borderStyle = .roundedRect
        textField.font = .preferredFont(forTextStyle: .title3)
        textField.adjustsFontForContentSizeCategory = true
        textField.clearButtonMode = .whileEditing
        textField.delegate = self
        textField.addTarget(self, action: #selector(textChanged), for: .editingChanged)

        primaryButton.configuration = .filled()
        primaryButton.configuration?.baseBackgroundColor = DriverTheme.brandColor
        primaryButton.configuration?.cornerStyle = .medium
        primaryButton.addTarget(self, action: #selector(primaryTapped), for: .touchUpInside)
        primaryButton.heightAnchor.constraint(greaterThanOrEqualToConstant: DriverTheme.controlHeight).isActive = true

        secondaryButton.addTarget(self, action: #selector(secondaryTapped), for: .touchUpInside)

        errorLabel.font = .preferredFont(forTextStyle: .footnote)
        errorLabel.adjustsFontForContentSizeCategory = true
        errorLabel.textColor = .systemRed
        errorLabel.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [
            titleLabel,
            subtitleLabel,
            textField,
            primaryButton,
            secondaryButton,
            errorLabel
        ])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 16
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            stack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor)
        ])
    }

    private func bind() {
        model.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.render(state)
            }
            .store(in: &cancellables)
    }

    private func render(_ state: AuthViewState) {
        switch state {
        case .phone(let phone):
            currentChallenge = nil
            stopResendTimer()
            titleLabel.text = "Driver sign in"
            subtitleLabel.text = "Use your Cambodia phone number. We will send a secure one-time code."
            textField.textContentType = .telephoneNumber
            textField.keyboardType = .phonePad
            textField.placeholder = "+855 12 345 678"
            if textField.text != phone.phone {
                textField.text = phone.phone
            }
            primaryButton.configuration?.title = "Continue"
            secondaryButton.setTitle("", for: .normal)
            secondaryButton.isHidden = true
            errorLabel.text = phone.errorMessage
            setSubmitting(phone.isSubmitting)

        case .code(let code):
            let previousChallenge = currentChallenge
            currentChallenge = code.challenge
            updateResendTimer(for: code)
            titleLabel.text = "Enter code"
            subtitleLabel.text = "We sent a \(code.challenge.codeLength)-digit code to \(code.challenge.phone)."
            textField.textContentType = .oneTimeCode
            textField.keyboardType = .numberPad
            textField.placeholder = String(repeating: "0", count: code.challenge.codeLength)
            if code.code.isEmpty, previousChallenge != code.challenge {
                textField.text = ""
            } else if code.code.isEmpty == false, textField.text != code.code {
                textField.text = code.code
            }
            primaryButton.configuration?.title = "Verify"
            let resendTitle = code.canResend ? "Resend code" : "Resend in \(code.resendRemainingSeconds)s"
            secondaryButton.setTitle("Change number · \(resendTitle)", for: .normal)
            secondaryButton.isHidden = false
            errorLabel.text = code.errorMessage
            setSubmitting(code.isSubmitting)

        case .authenticated:
            stopResendTimer()
            setSubmitting(false)
        }
    }

    private func updateResendTimer(for code: AuthCodeState) {
        if code.canResend || code.isSubmitting {
            stopResendTimer()
            return
        }
        guard resendTimer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard case .code(let current) = self.model.state else {
                self.stopResendTimer()
                return
            }
            if current.canResend {
                self.stopResendTimer()
            }
            self.render(self.model.state)
        }
        resendTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopResendTimer() {
        resendTimer?.invalidate()
        resendTimer = nil
    }

    private func setSubmitting(_ isSubmitting: Bool) {
        let title: String
        switch model.state {
        case .phone:
            title = "Continue"
        case .code:
            title = "Verify"
        case .authenticated:
            title = "Continue"
        }
        primaryButton.setDriverLoading(isSubmitting, title: title)
        textField.isEnabled = !isSubmitting
        secondaryButton.isEnabled = !isSubmitting
    }

    @objc private func primaryTapped() {
        switch model.state {
        case .phone:
            model.submitPhone(textField.text ?? "")
        case .code:
            model.submitCode(textField.text ?? "") { [weak self] session in
                self?.onOutput(.authenticated(session))
            }
        case .authenticated:
            break
        }
    }

    @objc private func secondaryTapped() {
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        let resendTitle: String
        if case .code(let code) = model.state, code.canResend == false {
            resendTitle = "Resend in \(code.resendRemainingSeconds)s"
        } else {
            resendTitle = "Resend Code"
        }
        alert.addAction(UIAlertAction(title: resendTitle, style: .default) { [weak self] _ in
            self?.model.resendCode()
        })
        alert.addAction(UIAlertAction(title: "Change Number", style: .default) { [weak self] _ in
            self?.model.editPhone()
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.popoverPresentationController?.sourceView = secondaryButton
        alert.popoverPresentationController?.sourceRect = secondaryButton.bounds
        present(alert, animated: true)
    }

    @objc private func textChanged() {
        guard let challenge = currentChallenge else { return }
        let digits = (textField.text ?? "").filter(\.isNumber)
        if digits != textField.text {
            textField.text = digits
        }
        if digits.count > challenge.codeLength {
            textField.text = String(digits.prefix(challenge.codeLength))
        }
    }
}

extension AuthViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        primaryTapped()
        return true
    }
}
