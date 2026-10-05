//
//  DriverEntryUIKitScreenFactory.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/5/26.
//

import DriverDomain
import DriverPresentation
import FeatureContracts
import UIKit

public final class DriverEntryUIKitScreenFactory: DriverEntryScreenFactory {
    public init() {}

    public func makeDriverEntryStatus(
        resolution: DriverEntryResolution,
        onOutput: @escaping (DriverEntryOutput) -> Void
    ) -> UIViewController {
        DriverEntryStatusViewController(resolution: resolution, onOutput: onOutput)
    }
}

final class DriverEntryStatusViewController: UIViewController {
    private let resolution: DriverEntryResolution
    private let onOutput: (DriverEntryOutput) -> Void

    init(resolution: DriverEntryResolution, onOutput: @escaping (DriverEntryOutput) -> Void) {
        self.resolution = resolution
        self.onOutput = onOutput
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = content.title
        configure()
    }

    private func configure() {
        let titleLabel = UILabel()
        titleLabel.text = content.title
        titleLabel.font = .preferredFont(forTextStyle: .largeTitle)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 0

        let detailLabel = UILabel()
        detailLabel.text = content.detail
        detailLabel.font = .preferredFont(forTextStyle: .body)
        detailLabel.adjustsFontForContentSizeCategory = true
        detailLabel.textColor = .secondaryLabel
        detailLabel.numberOfLines = 0

        let primary = UIButton(type: .system)
        primary.configuration = .filled()
        primary.configuration?.title = content.primaryTitle
        primary.configuration?.cornerStyle = .medium
        primary.addTarget(self, action: #selector(primaryTapped), for: .touchUpInside)
        primary.heightAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true

        let secondary = UIButton(type: .system)
        secondary.configuration = .bordered()
        secondary.configuration?.title = "Use another account"
        secondary.configuration?.cornerStyle = .medium
        secondary.addTarget(self, action: #selector(signOutTapped), for: .touchUpInside)
        secondary.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true

        let stack = UIStackView(arrangedSubviews: [titleLabel, detailLabel, primary, secondary])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 18
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            stack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor)
        ])
    }

    private var content: (title: String, detail: String, primaryTitle: String, output: DriverEntryOutput) {
        switch resolution.route {
        case .applicationReview:
            return ("Application in review", "Your documents have been submitted. The operations team will review them before training starts.", "Refresh status", .retry)
        case .training:
            return ("Training required", "Your application is approved for training. Complete the assigned training steps before you can operate.", "Refresh status", .retry)
        case .rejected:
            return ("Application rejected", "This account cannot continue driver onboarding. Uploads are not supported after rejection; contact support for available next steps.", "Refresh status", .retry)
        case .suspended:
            return ("Account restricted", "Your driver access is suspended. Scheduled mobility operations are disabled. Contact support if you need help.", "Refresh status", .retry)
        case .readiness:
            let missing = resolution.profile?.readiness.missing.map(\.displayTitle).joined(separator: ", ")
            let pending = resolution.profile?.readiness.pendingReview.map(\.displayTitle).joined(separator: ", ")
            let detail = [
                "You are approved but not operationally ready yet.",
                missing.flatMap { $0.isEmpty ? nil : "Missing: \($0)." },
                pending.flatMap { $0.isEmpty ? nil : "Pending review: \($0)." },
                resolution.profile?.readiness.hasActiveVehicle == false ? "An active vehicle assignment is required." : nil
            ].compactMap { $0 }.joined(separator: "\n")
            return ("Readiness required", detail, "View requirements", .showOnboarding)
        case .nonDriver:
            return ("Driver access needed", "This account does not have the DRIVER role. Driver registration is handled by administrators; this app cannot create a driver profile automatically.", "Use another account", .signOut)
        case .missingDriverProfile:
            return ("Driver profile missing", "Your account has driver access, but the backend did not return a driver profile. Contact support or use another account.", "Retry", .retry)
        case .onboarding:
            return ("Complete onboarding", "Upload the required documents before submitting your application.", "Open checklist", .showOnboarding)
        case .home:
            return ("Ready", "You are ready to operate.", "Continue", .retry)
        }
    }

    @objc private func primaryTapped() {
        onOutput(content.output)
    }

    @objc private func signOutTapped() {
        onOutput(.signOut)
    }
}
