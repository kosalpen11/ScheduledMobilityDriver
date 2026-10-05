//
//  DriverProfileSummaryViewController.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/5/26.
//

import Combine
import DesignSystem
import DriverPresentation
import FeatureContracts
import UIKit

final class DriverProfileSummaryViewController: UIViewController {
    private let model: DriverProfileViewModel
    private let onOutput: (DriverProfileSummaryOutput) -> Void
    private var cancellables = Set<AnyCancellable>()

    private let nameLabel = UILabel()
    private let phoneLabel = UILabel()
    private let statusLabel = UILabel()
    private let readinessLabel = UILabel()
    private let vehicleLabel = UILabel()
    private let messageLabel = UILabel()
    private let activity = UIActivityIndicatorView(style: .medium)
    private let viewProfileButton = UIButton(type: .system)
    private let signOutButton = UIButton(type: .system)

    init(model: DriverProfileViewModel, onOutput: @escaping (DriverProfileSummaryOutput) -> Void) {
        self.model = model
        self.onOutput = onOutput
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
        sheetPresentationController?.detents = [.medium(), .large()]
        sheetPresentationController?.prefersGrabberVisible = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Profile"
        view.backgroundColor = .systemBackground
        configureLayout()
        bind()
        Task { await model.load() }
    }

    private func configureLayout() {
        nameLabel.font = .preferredFont(forTextStyle: .title2).bold()
        phoneLabel.font = .preferredFont(forTextStyle: .subheadline)
        phoneLabel.textColor = .secondaryLabel
        statusLabel.font = .preferredFont(forTextStyle: .headline)
        readinessLabel.font = .preferredFont(forTextStyle: .body)
        vehicleLabel.font = .preferredFont(forTextStyle: .body)
        messageLabel.font = .preferredFont(forTextStyle: .footnote)
        messageLabel.textColor = .secondaryLabel
        messageLabel.numberOfLines = 0

        [nameLabel, phoneLabel, statusLabel, readinessLabel, vehicleLabel].forEach {
            $0.adjustsFontForContentSizeCategory = true
            $0.numberOfLines = 0
        }

        viewProfileButton.configuration = .borderedProminent()
        viewProfileButton.configuration?.baseBackgroundColor = DriverTheme.brandColor
        viewProfileButton.configuration?.title = "View profile"
        viewProfileButton.addTarget(self, action: #selector(viewProfileTapped), for: .touchUpInside)
        viewProfileButton.heightAnchor.constraint(greaterThanOrEqualToConstant: DriverTheme.controlHeight).isActive = true

        signOutButton.configuration = .bordered()
        signOutButton.configuration?.title = "Sign out"
        signOutButton.addTarget(self, action: #selector(signOutTapped), for: .touchUpInside)
        signOutButton.heightAnchor.constraint(greaterThanOrEqualToConstant: DriverTheme.controlHeight).isActive = true

        let identity = UIStackView(arrangedSubviews: [nameLabel, phoneLabel, statusLabel])
        identity.axis = .vertical
        identity.spacing = 6

        let readinessHeading = makeHeading("Readiness")
        let vehicleHeading = makeHeading("Vehicle")
        let accountHeading = makeHeading("Account")
        let readiness = UIStackView(arrangedSubviews: [readinessHeading, readinessLabel, vehicleHeading, vehicleLabel, accountHeading, signOutButton])
        readiness.axis = .vertical
        readiness.spacing = 8

        let stack = UIStackView(arrangedSubviews: [identity, readiness, messageLabel, viewProfileButton, activity])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 14
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -18),
            activity.heightAnchor.constraint(equalToConstant: 24)
        ])
    }

    private func makeHeading(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: .caption1).bold()
        label.textColor = .secondaryLabel
        label.adjustsFontForContentSizeCategory = true
        return label
    }

    private func bind() {
        model.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.render(state)
            }
            .store(in: &cancellables)
        model.$message
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.messageLabel.text = message
            }
            .store(in: &cancellables)
    }

    private func render(_ state: DriverProfileViewModel.State) {
        switch state {
        case .idle, .loading:
            activity.startAnimating()
            viewProfileButton.isHidden = true
            readinessLabel.text = "Checking your account readiness..."
            vehicleLabel.text = "Loading vehicle details..."
        case .loaded(let summary):
            activity.stopAnimating()
            viewProfileButton.isHidden = false
            nameLabel.text = summary.fullName
            phoneLabel.text = summary.maskedPhone
            statusLabel.text = summary.statusTitle
            statusLabel.textColor = summary.canOperate ? DriverTheme.brandColor : .label
            readinessLabel.text = summary.statusDetail
            vehicleLabel.text = "(summary.vehicleTitle)\n(summary.vehicleDetail)"
        case .failed(let message):
            activity.stopAnimating()
            viewProfileButton.isHidden = false
            readinessLabel.text = "Unable to load readiness."
            vehicleLabel.text = "Vehicle details are unavailable."
            messageLabel.text = message
        }
    }

    @objc private func viewProfileTapped() {
        onOutput(.viewProfile)
    }

    @objc private func signOutTapped() {
        onOutput(.logoutRequested)
    }
}

private extension UIFont {
    func bold() -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(.traitBold) else { return self }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
