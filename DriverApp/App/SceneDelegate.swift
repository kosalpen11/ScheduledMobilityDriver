//
//  SceneDelegate.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/4/26.
//

import Network
import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var coordinator: AppCoordinator?
    private var internetBannerController: InternetBannerController?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let navigationController = UINavigationController()
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = navigationController

        let compositionRoot = CompositionRoot(configuration: .staging)
        let coordinator = AppCoordinator(
            navigationController: navigationController,
            authFactory: compositionRoot.makeAuthFactory(),
            homeFactory: compositionRoot.makeHomeFactory(),
            driverProfileFactory: compositionRoot.makeDriverProfileFactory(),
            driverEntryFactory: compositionRoot.makeDriverEntryFactory(),
            tripFactory: compositionRoot.makeTripFactory(),
            restoreSession: compositionRoot.makeRestoreSessionUseCase(),
            loadDriverProfile: compositionRoot.makeLoadDriverProfileUseCase(),
            logout: compositionRoot.makeLogoutUseCase(),
            clearDriverSession: compositionRoot.makeClearDriverSessionUseCase()
        )

        self.window = window
        self.coordinator = coordinator
        window.makeKeyAndVisible()
        let internetBannerController = InternetBannerController(window: window)
        self.internetBannerController = internetBannerController
        internetBannerController.start()
        coordinator.start()
    }
}

@MainActor
private final class InternetBannerController {
    private let window: UIWindow
    private let monitor = InternetConnectionMonitor()
    private let banner = UIView()
    private let label = UILabel()
    private let activity = UIActivityIndicatorView(style: .medium)
    private var topConstraint: NSLayoutConstraint?
    private var isVisible = false

    init(window: UIWindow) {
        self.window = window
        configureBanner()
    }

    func start() {
        monitor.onStatusChange = { [weak self] isConnected in
            Task { @MainActor in
                self?.setVisible(isConnected == false)
            }
        }
        monitor.start()
    }

    private func configureBanner() {
        banner.translatesAutoresizingMaskIntoConstraints = false
        banner.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.42, green: 0.10, blue: 0.09, alpha: 0.96)
                : UIColor(red: 0.72, green: 0.12, blue: 0.10, alpha: 0.96)
        }
        banner.layer.cornerRadius = 8
        banner.layer.cornerCurve = .continuous
        banner.layer.shadowColor = UIColor.black.cgColor
        banner.layer.shadowOpacity = 0.18
        banner.layer.shadowRadius = 12
        banner.layer.shadowOffset = CGSize(width: 0, height: 4)

        activity.translatesAutoresizingMaskIntoConstraints = false
        activity.color = .white

        label.text = "Reconnecting..."
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .white
        label.numberOfLines = 1
        label.minimumScaleFactor = 0.85
        label.adjustsFontSizeToFitWidth = true

        let stack = UIStackView(arrangedSubviews: [activity, label])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 8
        banner.addSubview(stack)
        window.addSubview(banner)

        topConstraint = banner.topAnchor.constraint(equalTo: window.safeAreaLayoutGuide.topAnchor, constant: -64)
        NSLayoutConstraint.activate([
            topConstraint!,
            banner.leadingAnchor.constraint(equalTo: window.leadingAnchor, constant: 16),
            banner.trailingAnchor.constraint(equalTo: window.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: banner.topAnchor, constant: 10),
            stack.leadingAnchor.constraint(equalTo: banner.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: banner.trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: banner.bottomAnchor, constant: -10),
            activity.widthAnchor.constraint(equalToConstant: 18),
            activity.heightAnchor.constraint(equalToConstant: 18)
        ])
        banner.alpha = 0
        banner.isAccessibilityElement = true
        banner.accessibilityLabel = "Reconnecting"
    }

    private func setVisible(_ visible: Bool) {
        guard visible != isVisible else { return }
        isVisible = visible
        topConstraint?.constant = visible ? 8 : -64
        UIView.animate(
            withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.22,
            delay: 0,
            options: [.beginFromCurrentState, .curveEaseOut]
        ) {
            self.banner.alpha = visible ? 1 : 0
            self.window.layoutIfNeeded()
        }

        if visible {
            activity.startAnimating()
        } else {
            activity.stopAnimating()
        }
    }
}

private final class InternetConnectionMonitor: @unchecked Sendable {
    var onStatusChange: (@Sendable (Bool) -> Void)?

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.scheduledmobility.driver.internet-monitor")
    private var lastStatus: NWPath.Status?

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            guard path.status != self.lastStatus else { return }
            self.lastStatus = path.status
            self.onStatusChange?(path.status == .satisfied)
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
