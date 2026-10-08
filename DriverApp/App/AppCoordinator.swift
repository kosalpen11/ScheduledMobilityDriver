//
//  AppCoordinator.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/4/26.
//

import DesignSystem
import DriverDomain
import FeatureContracts
import UIKit

@MainActor
final class AppCoordinator {
    private let navigationController: UINavigationController
    private let authFactory: any AuthScreenFactory
    private let homeFactory: any HomeScreenFactory
    private let driverProfileFactory: any DriverProfileScreenFactory
    private let driverEntryFactory: any DriverEntryScreenFactory
    private let tripFactory: any TripScreenFactory
    private let restoreSession: RestoreSessionUseCase
    private let loadDriverProfile: LoadDriverProfileUseCase
    private let logout: LogoutUseCase
    private let clearDriverSession: ClearDriverSessionUseCase
    private var session: AuthenticatedSession?
    private var entryTask: Task<Void, Never>?
    private var isSigningOut = false
    private let entryResolver = DriverEntryResolver()

    init(
        navigationController: UINavigationController,
        authFactory: any AuthScreenFactory,
        homeFactory: any HomeScreenFactory,
        driverProfileFactory: any DriverProfileScreenFactory,
        driverEntryFactory: any DriverEntryScreenFactory,
        tripFactory: any TripScreenFactory,
        restoreSession: RestoreSessionUseCase,
        loadDriverProfile: LoadDriverProfileUseCase,
        logout: LogoutUseCase,
        clearDriverSession: ClearDriverSessionUseCase
    ) {
        self.navigationController = navigationController
        self.authFactory = authFactory
        self.homeFactory = homeFactory
        self.driverProfileFactory = driverProfileFactory
        self.driverEntryFactory = driverEntryFactory
        self.tripFactory = tripFactory
        self.restoreSession = restoreSession
        self.loadDriverProfile = loadDriverProfile
        self.logout = logout
        self.clearDriverSession = clearDriverSession
    }

    func start() {
        entryTask?.cancel()
        showRestoringSession()
        entryTask = Task { [weak self] in
            guard let self else { return }
            do {
                if let session = try await restoreSession() {
                    await resolveEntry(session: session, animated: false)
                } else {
                    showAuth(animated: false)
                }
            } catch {
                showRestoreFailed(message: Self.message(for: error))
            }
        }
    }

    private func showAuth(animated: Bool) {
        let auth = authFactory.makeAuth { [weak self] output in
            guard let self else { return }
            switch output {
            case .authenticated(let session):
                Task { await self.resolveEntry(session: session, animated: true) }
            case .developmentHomeBypass:
                self.showHome(session: nil, animated: true)
            }
        }
        navigationController.setViewControllers([auth], animated: animated)
    }

    private func showHome(
        session: AuthenticatedSession?,
        animated: Bool
    ) {
        self.session = session
        let home = homeFactory.makeHome { [weak self] output in
            self?.handle(output)
        }
        navigationController.setViewControllers([home], animated: animated)
    }

    private func resolveEntry(session: AuthenticatedSession, animated: Bool) async {
        self.session = session
        showResolvingDriver()

        do {
            let profile: DriverProfileDetail?
            if session.user.isDriver {
                profile = try await loadDriverProfile()
            } else {
                profile = nil
            }
            guard !Task.isCancelled else { return }
            route(entryResolver.resolve(session: session, profile: profile), session: session, animated: animated)
        } catch DriverProfileFailure.notFound(_) {
            let resolution = entryResolver.resolve(session: session, profile: nil)
            route(resolution, session: session, animated: animated)
        } catch DriverProfileFailure.unauthorized {
            await signOut()
        } catch {
            showDriverLookupFailed(message: Self.message(for: error), session: session)
        }
    }

    private func route(_ resolution: DriverEntryResolution, session: AuthenticatedSession, animated: Bool) {
        switch resolution.route {
        case .home:
            showHome(session: session, animated: animated)
        case .onboarding:
            let controller = driverProfileFactory.makeDriverProfile { [weak self] output in
                if case .logoutRequested = output {
                    self?.logoutTapped()
                }
            }
            navigationController.setViewControllers([controller], animated: animated)
        default:
            let controller = driverEntryFactory.makeDriverEntryStatus(resolution: resolution) { [weak self] output in
                guard let self else { return }
                switch output {
                case .signOut:
                    logoutTapped()
                case .retry:
                    Task { await self.resolveEntry(session: session, animated: false) }
                case .showOnboarding:
                    showProfile()
                }
            }
            navigationController.setViewControllers([controller], animated: animated)
        }
    }

    private func showResolvingDriver() {
        navigationController.setViewControllers([
            AppLoadingViewController(
                title: "Checking driver status",
                message: "We’re getting your profile and requirements ready.",
                style: .default
            )
        ], animated: false)
    }

    private func showRestoringSession() {
        navigationController.setViewControllers([
            AppLoadingViewController(
                title: "Scheduled Mobility",
                message: "Restoring your driver session.",
                style: .sessionRestore
            )
        ], animated: false)
    }

    private func showSigningOut() {
        navigationController.setViewControllers([
            AppLoadingViewController(
                title: "Signing out",
                message: "Ending your driver session.",
                style: .default
            )
        ], animated: true)
    }

    private func showRestoreFailed(message: String) {
        let controller = UIViewController()
        controller.view.backgroundColor = .systemBackground

        let title = UILabel()
        title.translatesAutoresizingMaskIntoConstraints = false
        title.text = "Unable to restore session"
        title.font = .preferredFont(forTextStyle: .title3)
        title.adjustsFontForContentSizeCategory = true
        title.textAlignment = .center

        let detail = UILabel()
        detail.translatesAutoresizingMaskIntoConstraints = false
        detail.text = message
        detail.font = .preferredFont(forTextStyle: .body)
        detail.adjustsFontForContentSizeCategory = true
        detail.textAlignment = .center
        detail.textColor = .secondaryLabel
        detail.numberOfLines = 0

        let retry = UIButton(type: .system)
        retry.translatesAutoresizingMaskIntoConstraints = false
        retry.configuration = .borderedProminent()
        retry.configuration?.title = "Retry"
        retry.addTarget(self, action: #selector(retryRestoreTapped), for: .touchUpInside)

        let signIn = UIButton(type: .system)
        signIn.translatesAutoresizingMaskIntoConstraints = false
        signIn.configuration = .bordered()
        signIn.configuration?.title = "Sign Out"
        signIn.addTarget(self, action: #selector(signInTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [title, detail, retry, signIn])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .fill
        controller.view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            stack.centerYAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.centerYAnchor),
            retry.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
            signIn.heightAnchor.constraint(greaterThanOrEqualToConstant: 48)
        ])

        navigationController.setViewControllers([controller], animated: false)
    }

    @objc private func retryRestoreTapped() {
        start()
    }

    @objc private func signInTapped() {
        logoutTapped()
    }

    private func showDriverLookupFailed(message: String, session: AuthenticatedSession) {
        let controller = UIViewController()
        controller.view.backgroundColor = .systemBackground

        let title = UILabel()
        title.translatesAutoresizingMaskIntoConstraints = false
        title.text = "Unable to check driver status"
        title.font = .preferredFont(forTextStyle: .title3)
        title.adjustsFontForContentSizeCategory = true
        title.textAlignment = .center

        let detail = UILabel()
        detail.translatesAutoresizingMaskIntoConstraints = false
        detail.text = message
        detail.font = .preferredFont(forTextStyle: .body)
        detail.adjustsFontForContentSizeCategory = true
        detail.textAlignment = .center
        detail.textColor = .secondaryLabel
        detail.numberOfLines = 0

        let retry = UIButton(type: .system)
        retry.translatesAutoresizingMaskIntoConstraints = false
        retry.configuration = .borderedProminent()
        retry.configuration?.title = "Retry"
        retry.addAction(UIAction { [weak self] _ in
            Task { await self?.resolveEntry(session: session, animated: false) }
        }, for: .touchUpInside)

        let signOut = UIButton(type: .system)
        signOut.translatesAutoresizingMaskIntoConstraints = false
        signOut.configuration = .bordered()
        signOut.configuration?.title = "Sign Out"
        signOut.addAction(UIAction { [weak self] _ in
            self?.logoutTapped()
        }, for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [title, detail, retry, signOut])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 16
        controller.view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            stack.centerYAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.centerYAnchor),
            retry.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
            signOut.heightAnchor.constraint(greaterThanOrEqualToConstant: 48)
        ])

        navigationController.setViewControllers([controller], animated: false)
    }

    private func handle(_ output: HomeOutput) {
        switch output {
        case .showTrip(let id):
            showTrip(id: id)
        case .showProfile:
            showProfileSummary()
        case .openProfile:
            showProfile()
        }
    }

    private func showTrip(id: UUID) {
        let controller = tripFactory.makeTripDetail(id: id) { [weak self] output in
            switch output {
            case .tripChanged:
                self?.navigationController.viewControllers.first?.view.setNeedsLayout()
            }
        }
        navigationController.pushViewController(controller, animated: true)
    }

    private func showProfile() {
        let controller = driverProfileFactory.makeDriverProfile { [weak self] output in
            switch output {
            case .logoutRequested:
                self?.logoutTapped()
            }
        }
        navigationController.pushViewController(controller, animated: true)
    }

    private func showProfileSummary() {
        let summary = driverProfileFactory.makeDriverProfileSummary { [weak self] output in
            guard let self else { return }
            switch output {
            case .viewProfile:
                navigationController.dismiss(animated: true) {
                    self.showProfile()
                }
            case .logoutRequested:
                navigationController.dismiss(animated: true) {
                    self.logoutTapped()
                }
            }
        }
        let sheet = UINavigationController(rootViewController: summary)
        sheet.modalPresentationStyle = .pageSheet
        sheet.sheetPresentationController?.detents = [.medium(), .large()]
        sheet.sheetPresentationController?.prefersGrabberVisible = true
        navigationController.present(sheet, animated: true)
    }

    private func logoutTapped() {
        Task { [weak self] in
            guard let self else { return }
            await signOut()
        }
    }

    private func signOut() async {
        guard isSigningOut == false else { return }
        isSigningOut = true
        entryTask?.cancel()
        showSigningOut()
        await clearDriverSession()
        await logout()
        session = nil
        isSigningOut = false
        showAuth(animated: true)
    }

    private static func message(for error: Error) -> String {
        switch error {
        case AuthFailure.validation(let message),
             AuthFailure.invalidOTP(let message),
             AuthFailure.inactiveAccount(let message),
             AuthFailure.transient(let message),
             AuthFailure.server(let message):
            return message
        case AuthFailure.rateLimited(_, let message):
            return message
        case AuthFailure.invalidRefreshToken:
            return "Your session expired. Sign in again."
        case AuthFailure.unauthorized:
            return "Sign in again to continue."
        case AuthFailure.forbidden:
            return "This account is not allowed to use the driver app."
        case DriverProfileFailure.validation(let message),
             DriverProfileFailure.conflict(let message),
             DriverProfileFailure.transient(let message),
             DriverProfileFailure.server(let message),
             DriverProfileFailure.notFound(let message):
            return message
        case DriverProfileFailure.unauthorized:
            return "Sign in again to continue."
        case DriverProfileFailure.forbidden:
            return "This account is not allowed to access the driver profile."
        default:
            return error.localizedDescription
        }
    }

    private func showPlaceholder(title: String, message: String) {
        let controller = UIViewController()
        controller.title = title
        controller.view.backgroundColor = .systemBackground

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = message
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.textAlignment = .center
        controller.view.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            label.centerYAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.centerYAnchor)
        ])

        navigationController.pushViewController(controller, animated: true)
    }
}

private final class AppLoadingViewController: UIViewController {
    enum Style {
        case `default`
        case sessionRestore
    }

    private let loadingTitle: String
    private let message: String
    private let style: Style
    private let restoreMarkView = DriverSessionRestoreMarkView()

    init(title: String, message: String, style: Style) {
        self.loadingTitle = title
        self.message = message
        self.style = style
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        configureLayout()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if style == .sessionRestore {
            restoreMarkView.startAnimating()
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        restoreMarkView.stopAnimating()
    }

    private func configureLayout() {
        let markContainer = UIView()
        markContainer.translatesAutoresizingMaskIntoConstraints = false
        markContainer.backgroundColor = DriverTheme.brandColor.withAlphaComponent(0.10)
        markContainer.layer.cornerRadius = 14
        markContainer.layer.cornerCurve = .continuous

        let icon = UIImageView(image: UIImage(systemName: "figure.roll"))
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.tintColor = DriverTheme.brandColor
        icon.contentMode = .scaleAspectFit

        let useRestoreMark = style == .sessionRestore
        if useRestoreMark {
            markContainer.addSubview(restoreMarkView)
        } else {
            markContainer.addSubview(icon)
        }

        let titleLabel = UILabel()
        titleLabel.text = loadingTitle
        titleLabel.font = .systemFont(ofSize: UIFont.preferredFont(forTextStyle: .title2).pointSize, weight: .bold)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0

        let messageLabel = UILabel()
        messageLabel.text = message
        messageLabel.font = .preferredFont(forTextStyle: .body)
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.textColor = .secondaryLabel
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0

        let activity = UIActivityIndicatorView(style: .medium)
        activity.color = DriverTheme.brandColor
        activity.startAnimating()

        let progressPill = UIStackView(arrangedSubviews: [activity, messageLabel])
        progressPill.axis = .horizontal
        progressPill.alignment = .center
        progressPill.spacing = 10
        progressPill.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14)
        progressPill.isLayoutMarginsRelativeArrangement = true
        progressPill.backgroundColor = DriverTheme.cardColor
        progressPill.layer.cornerRadius = DriverTheme.cardCornerRadius
        progressPill.layer.cornerCurve = .continuous

        let stack = UIStackView(arrangedSubviews: [markContainer, titleLabel, progressPill])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 18
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            markContainer.widthAnchor.constraint(greaterThanOrEqualToConstant: 72),
            markContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 72),
            progressPill.leadingAnchor.constraint(greaterThanOrEqualTo: stack.leadingAnchor),
            progressPill.trailingAnchor.constraint(lessThanOrEqualTo: stack.trailingAnchor),
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -28),
            stack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor)
        ])

        if useRestoreMark {
            NSLayoutConstraint.activate([
                restoreMarkView.centerXAnchor.constraint(equalTo: markContainer.centerXAnchor),
                restoreMarkView.centerYAnchor.constraint(equalTo: markContainer.centerYAnchor),
                restoreMarkView.topAnchor.constraint(greaterThanOrEqualTo: markContainer.topAnchor, constant: 8),
                restoreMarkView.leadingAnchor.constraint(greaterThanOrEqualTo: markContainer.leadingAnchor, constant: 8),
                restoreMarkView.trailingAnchor.constraint(lessThanOrEqualTo: markContainer.trailingAnchor, constant: -8),
                restoreMarkView.bottomAnchor.constraint(lessThanOrEqualTo: markContainer.bottomAnchor, constant: -8)
            ])
        } else {
            NSLayoutConstraint.activate([
                icon.centerXAnchor.constraint(equalTo: markContainer.centerXAnchor),
                icon.centerYAnchor.constraint(equalTo: markContainer.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 28),
                icon.heightAnchor.constraint(equalToConstant: 28)
            ])
        }
    }
}
