//
//  HomeViewController.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/4/26.
//

import Combine
import DesignSystem
import DriverDomain
import DriverPresentation
import FeatureContracts
import FloatingPanel
import MapKit
import UIKit

final class HomeViewController: UIViewController {
    private let model: HomeViewModel
    private let onOutput: (HomeOutput) -> Void
    private let resolver = TripActionResolver()
    private var cancellables = Set<AnyCancellable>()
    private var visibleTrips: [ScheduledTrip] = []

    private let mapView = MKMapView()
    private let panelView = UIView()
    private let panelContentController = UIViewController()
    private let floatingPanelController = FloatingPanelController()
    private let headerLabel = UILabel()
    private let statusLabel = UILabel()
    private let nextTripHeadingLabel = UILabel()
    private let assignmentsHeadingLabel = UILabel()
    private let nextTripCard = UIView()
    private let nextTripEyebrowLabel = UILabel()
    private let nextTripTimeLabel = UILabel()
    private let nextTripRouteLabel = UILabel()
    private let nextTripRoleLabel = UILabel()
    private let availabilityButton = UIButton(type: .system)
    private let profileShortcutButton = UIButton(type: .system)
    private let retryButton = UIButton(type: .system)
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let messageLabel = UILabel()

    init(model: HomeViewModel, onOutput: @escaping (HomeOutput) -> Void) {
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
        title = "Driver"
        view.backgroundColor = .systemBackground
        edgesForExtendedLayout = [.top, .bottom]
        extendedLayoutIncludesOpaqueBars = true
        configureNavigation()
        configureMap()
        configurePanel()
        configureFloatingPanel()
        bind()
        model.load()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if model.state.contentSnapshot != nil {
            model.refresh()
        }
    }

    private func configureNavigation() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        navigationController?.navigationBar.standardAppearance = appearance
        navigationController?.navigationBar.scrollEdgeAppearance = appearance

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "person.crop.circle"),
            style: .plain,
            target: self,
            action: #selector(showProfile)
        )
        navigationItem.rightBarButtonItem?.accessibilityLabel = "Profile"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "arrow.clockwise"),
            style: .plain,
            target: self,
            action: #selector(retryTapped)
        )
        navigationItem.leftBarButtonItem?.accessibilityLabel = "Refresh"
        navigationController?.navigationBar.prefersLargeTitles = false
    }

    private func configureMap() {
        mapView.translatesAutoresizingMaskIntoConstraints = false
        mapView.pointOfInterestFilter = .excludingAll
        mapView.showsUserLocation = true
        view.addSubview(mapView)

        NSLayoutConstraint.activate([
            mapView.topAnchor.constraint(equalTo: view.topAnchor),
            mapView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mapView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 11.5564, longitude: 104.9282),
            latitudinalMeters: 9_000,
            longitudinalMeters: 9_000
        )
        mapView.setRegion(region, animated: false)
    }

    private func configurePanel() {
        panelView.translatesAutoresizingMaskIntoConstraints = false
        panelView.backgroundColor = DriverTheme.panelColor
        panelView.layer.cornerRadius = DriverTheme.cornerRadius + 4
        panelView.layer.cornerCurve = .continuous
        panelView.layer.shadowColor = UIColor.black.cgColor
        panelView.layer.shadowOpacity = traitCollection.userInterfaceStyle == .dark ? 0.35 : 0.16
        panelView.layer.shadowRadius = 22
        panelView.layer.shadowOffset = CGSize(width: 0, height: 10)

        let statusStack = UIStackView(arrangedSubviews: [headerLabel, statusLabel])
        statusStack.axis = .vertical
        statusStack.spacing = 3

        let topRow = UIStackView(arrangedSubviews: [statusStack, availabilityButton])
        topRow.axis = .horizontal
        topRow.alignment = .center
        topRow.spacing = 12

        configureNextTripCard()

        let stack = UIStackView(arrangedSubviews: [topRow, nextTripHeadingLabel, nextTripCard, assignmentsHeadingLabel, messageLabel, profileShortcutButton, retryButton, tableView])
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        panelView.addSubview(stack)

        headerLabel.text = "Driver availability"
        headerLabel.font = .preferredFont(forTextStyle: .caption1)
        headerLabel.adjustsFontForContentSizeCategory = true
        headerLabel.textColor = .secondaryLabel
        headerLabel.numberOfLines = 1

        statusLabel.font = .preferredFont(forTextStyle: .title3)
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.numberOfLines = 0

        [nextTripHeadingLabel, assignmentsHeadingLabel].forEach {
            $0.font = .preferredFont(forTextStyle: .headline)
            $0.adjustsFontForContentSizeCategory = true
            $0.textColor = .label
        }
        nextTripHeadingLabel.text = "Next scheduled trip"
        assignmentsHeadingLabel.text = "Today's assignments"

        availabilityButton.configuration = .filled()
        availabilityButton.configuration?.cornerStyle = .medium
        availabilityButton.configuration?.baseBackgroundColor = DriverTheme.brandColor
        availabilityButton.configuration?.baseForegroundColor = .white
        availabilityButton.configuration?.image = UIImage(systemName: "power")
        availabilityButton.configuration?.imagePadding = 8
        availabilityButton.titleLabel?.adjustsFontForContentSizeCategory = true
        availabilityButton.addTarget(self, action: #selector(toggleAvailability), for: .touchUpInside)
        availabilityButton.accessibilityHint = "Changes whether you can receive scheduled mobility work."

        profileShortcutButton.configuration = .borderedProminent()
        profileShortcutButton.configuration?.image = UIImage(systemName: "person.text.rectangle")
        profileShortcutButton.configuration?.imagePadding = 8
        profileShortcutButton.configuration?.baseBackgroundColor = DriverTheme.accentColor
        profileShortcutButton.configuration?.baseForegroundColor = .white
        profileShortcutButton.configuration?.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14)
        profileShortcutButton.addTarget(self, action: #selector(openProfileShortcut), for: .touchUpInside)
        profileShortcutButton.titleLabel?.adjustsFontForContentSizeCategory = true
        profileShortcutButton.titleLabel?.lineBreakMode = .byClipping
        profileShortcutButton.titleLabel?.minimumScaleFactor = 0.85
        profileShortcutButton.titleLabel?.adjustsFontSizeToFitWidth = true
        profileShortcutButton.accessibilityHint = "Opens your driver profile requirements."
        profileShortcutButton.isHidden = true

        messageLabel.font = .preferredFont(forTextStyle: .subheadline)
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.textColor = .secondaryLabel
        messageLabel.numberOfLines = 0

        retryButton.configuration = .borderedProminent()
        retryButton.configuration?.title = "Retry"
        retryButton.configuration?.image = UIImage(systemName: "arrow.clockwise")
        retryButton.configuration?.imagePadding = 8
        retryButton.configuration?.baseBackgroundColor = DriverTheme.brandColor
        retryButton.configuration?.baseForegroundColor = .white
        retryButton.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)
        retryButton.accessibilityHint = "Reloads scheduled trips and availability."

        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 92
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.showsVerticalScrollIndicator = false
        tableView.register(TripCell.self, forCellReuseIdentifier: TripCell.reuseIdentifier)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: panelView.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: panelView.leadingAnchor, constant: DriverTheme.innerMargin),
            stack.trailingAnchor.constraint(equalTo: panelView.trailingAnchor, constant: -DriverTheme.innerMargin),
            stack.bottomAnchor.constraint(equalTo: panelView.bottomAnchor, constant: -DriverTheme.innerMargin),
            availabilityButton.heightAnchor.constraint(greaterThanOrEqualToConstant: DriverTheme.controlHeight),
            availabilityButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 150),
            profileShortcutButton.heightAnchor.constraint(greaterThanOrEqualToConstant: DriverTheme.controlHeight),
            retryButton.heightAnchor.constraint(greaterThanOrEqualToConstant: DriverTheme.controlHeight),
            tableView.heightAnchor.constraint(greaterThanOrEqualToConstant: 140)
        ])
    }

    private func configureFloatingPanel() {
        panelContentController.view = panelView
        floatingPanelController.layout = HomeFloatingPanelLayout()
        floatingPanelController.set(contentViewController: panelContentController)
        floatingPanelController.track(scrollView: tableView)
        floatingPanelController.addPanel(toParent: self)
    }

    private func configureNextTripCard() {
        nextTripCard.backgroundColor = DriverTheme.cardColor
        nextTripCard.layer.cornerRadius = DriverTheme.cardCornerRadius
        nextTripCard.layer.cornerCurve = .continuous
        nextTripCard.isAccessibilityElement = true

        nextTripEyebrowLabel.text = "Next scheduled pickup"
        nextTripEyebrowLabel.font = .preferredFont(forTextStyle: .caption1)
        nextTripEyebrowLabel.textColor = .secondaryLabel

        nextTripTimeLabel.font = .preferredFont(forTextStyle: .title2)
        nextTripTimeLabel.textColor = .label

        nextTripRouteLabel.font = .preferredFont(forTextStyle: .subheadline)
        nextTripRouteLabel.textColor = .secondaryLabel
        nextTripRouteLabel.numberOfLines = 0

        nextTripRoleLabel.font = .preferredFont(forTextStyle: .caption1)
        nextTripRoleLabel.textColor = DriverTheme.brandColor
        nextTripRoleLabel.numberOfLines = 1

        [nextTripEyebrowLabel, nextTripTimeLabel, nextTripRouteLabel, nextTripRoleLabel].forEach {
            $0.adjustsFontForContentSizeCategory = true
        }

        let stack = UIStackView(arrangedSubviews: [nextTripEyebrowLabel, nextTripTimeLabel, nextTripRouteLabel, nextTripRoleLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 5
        nextTripCard.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: nextTripCard.topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: nextTripCard.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: nextTripCard.trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: nextTripCard.bottomAnchor, constant: -14)
        ])
    }

    private func bind() {
        model.$state
            .combineLatest(model.$profileGate)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state, gate in
                self?.render(state, profileGate: gate)
            }
            .store(in: &cancellables)
    }

    private func render(_ state: HomeViewState, profileGate: HomeProfileGate) {
        if let snapshot = state.contentSnapshot {
            visibleTrips = snapshot.trips
            let isAvailable = snapshot.availability == .available
            statusLabel.text = profileGate.prompt?.title ?? HomePresentationFormatting.title(for: snapshot.availability)
            statusLabel.textColor = profileGate.allowsAvailability ? DriverTheme.statusColor(isAvailable: isAvailable) : DriverTheme.accentColor
            availabilityButton.configuration?.title = isAvailable ? "Go unavailable" : "Go available"
            availabilityButton.configuration?.baseBackgroundColor = isAvailable ? DriverTheme.destructiveColor : DriverTheme.brandColor
            messageLabel.text = message(for: state, snapshot: snapshot, profileGate: profileGate)
            renderNextTrip(snapshot.nextTrip)
            renderAnnotations(for: snapshot.trips)
        } else {
            visibleTrips = []
            statusLabel.text = "Loading scheduled work"
            statusLabel.textColor = .label
            availabilityButton.configuration?.title = "Availability"
            availabilityButton.configuration?.baseBackgroundColor = DriverTheme.brandColor
            messageLabel.text = message(for: state, snapshot: nil, profileGate: profileGate)
            renderNextTrip(nil)
        }

        availabilityButton.isEnabled = !state.isBusy && state.contentSnapshot != nil && profileGate.allowsAvailability
        availabilityButton.alpha = availabilityButton.isEnabled ? 1 : 0.55
        profileShortcutButton.isHidden = profileGate.prompt == nil
        profileShortcutButton.configuration?.title = profileGate.prompt?.actionTitle
        profileShortcutButton.isEnabled = !state.isBusy
        retryButton.isHidden = !isRefreshFailure(state)
        retryButton.isEnabled = !state.isBusy
        navigationItem.leftBarButtonItem?.isEnabled = !state.isBusy
        tableView.reloadData()
    }

    private func isRefreshFailure(_ state: HomeViewState) -> Bool {
        if case .refreshFailed = state {
            return true
        }
        if case .failure = state {
            return true
        }
        return false
    }

    private func renderNextTrip(_ trip: ScheduledTrip?) {
        guard let trip else {
            nextTripTimeLabel.text = "--"
            nextTripRouteLabel.text = "No scheduled pickup assigned."
            nextTripRoleLabel.text = "Stand by"
            nextTripCard.accessibilityLabel = "No scheduled pickup assigned."
            return
        }

        let time = HomePresentationFormatting.timeFormatter.string(from: trip.scheduledPickupAt)
        let role = HomePresentationFormatting.title(for: trip.assignment)
        nextTripTimeLabel.text = time
        nextTripRouteLabel.text = "\(trip.pickupName) to \(trip.dropoffName)"
        nextTripRoleLabel.text = "\(role) assignment"
        nextTripRoleLabel.textColor = trip.assignment == .primary ? DriverTheme.brandColor : DriverTheme.accentColor
        nextTripCard.accessibilityLabel = "Next scheduled pickup at \(time), \(role), from \(trip.pickupName) to \(trip.dropoffName)."
    }

    private func message(for state: HomeViewState, snapshot: HomeSnapshot?, profileGate: HomeProfileGate) -> String {
        if let prompt = profileGate.prompt {
            return prompt.detail
        }
        switch state {
        case .initial, .loading:
            return "Checking assignments..."
        case .empty:
            return "No scheduled trips are assigned today."
        case .content, .refreshing, .updatingAvailability:
            guard let nextTrip = snapshot?.nextTrip else { return "No scheduled trips are assigned today." }
            let time = HomePresentationFormatting.timeFormatter.string(from: nextTrip.scheduledPickupAt)
            return "Next pickup at \(time) from \(nextTrip.pickupName)."
        case .refreshFailed(_, let message), .failure(let message):
            return message
        }
    }

    private func renderAnnotations(for trips: [ScheduledTrip]) {
        mapView.removeAnnotations(mapView.annotations)
        let annotations = trips.map { trip in
            let annotation = MKPointAnnotation()
            annotation.title = trip.pickupName
            annotation.subtitle = HomePresentationFormatting.title(for: trip.assignment)
            annotation.coordinate = CLLocationCoordinate2D(
                latitude: trip.pickupCoordinate.latitude,
                longitude: trip.pickupCoordinate.longitude
            )
            return annotation
        }
        mapView.addAnnotations(annotations)
    }

    @objc private func toggleAvailability() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        model.toggleAvailability()
    }

    @objc private func openProfileShortcut() {
        onOutput(.openProfile)
    }

    @objc private func showProfile() {
        onOutput(.showProfile)
    }

    @objc private func retryTapped() {
        model.refresh()
    }

}

private final class HomeFloatingPanelLayout: FloatingPanelBottomLayout {
    override var initialState: FloatingPanelState { .half }

    override var anchors: [FloatingPanelState: FloatingPanelLayoutAnchoring] {
        [
            .full: FloatingPanelLayoutAnchor(absoluteInset: 18, edge: .top, referenceGuide: .safeArea),
            .half: FloatingPanelLayoutAnchor(fractionalInset: 0.52, edge: .bottom, referenceGuide: .safeArea),
            .tip: FloatingPanelLayoutAnchor(absoluteInset: 92, edge: .bottom, referenceGuide: .safeArea)
        ]
    }

    override func backdropAlpha(for state: FloatingPanelState) -> CGFloat {
        0
    }
}

extension HomeViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        visibleTrips.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: TripCell.reuseIdentifier, for: indexPath) as! TripCell
        cell.configure(with: visibleTrips[indexPath.row], action: resolver.nextAction(for: visibleTrips[indexPath.row]))
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        onOutput(.showTrip(visibleTrips[indexPath.row].id))
    }
}

private final class TripCell: UITableViewCell {
    static let reuseIdentifier = "TripCell"

    private let containerView = UIView()
    private let roleView = UIView()
    private let roleIconView = UIImageView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let actionLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        accessoryType = .disclosureIndicator
        backgroundColor = .clear
        selectionStyle = .default

        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.backgroundColor = .clear
        contentView.addSubview(containerView)

        roleView.translatesAutoresizingMaskIntoConstraints = false
        roleView.layer.cornerRadius = DriverTheme.cardCornerRadius
        roleView.layer.cornerCurve = .continuous

        roleIconView.translatesAutoresizingMaskIntoConstraints = false
        roleIconView.contentMode = .scaleAspectFit
        roleIconView.tintColor = .white
        roleView.addSubview(roleIconView)

        let stack = UIStackView(arrangedSubviews: [titleLabel, detailLabel, actionLabel])
        stack.axis = .vertical
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(roleView)
        containerView.addSubview(stack)

        titleLabel.font = .preferredFont(forTextStyle: .headline)
        detailLabel.font = .preferredFont(forTextStyle: .subheadline)
        actionLabel.font = .preferredFont(forTextStyle: .caption1).bold()
        detailLabel.textColor = .secondaryLabel
        actionLabel.textColor = DriverTheme.brandColor

        [titleLabel, detailLabel, actionLabel].forEach {
            $0.adjustsFontForContentSizeCategory = true
            $0.numberOfLines = 0
        }

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            containerView.heightAnchor.constraint(greaterThanOrEqualToConstant: DriverTheme.minimumTouchTarget),

            roleView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            roleView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 8),
            roleView.widthAnchor.constraint(equalToConstant: 36),
            roleView.heightAnchor.constraint(equalToConstant: 36),

            roleIconView.centerXAnchor.constraint(equalTo: roleView.centerXAnchor),
            roleIconView.centerYAnchor.constraint(equalTo: roleView.centerYAnchor),
            roleIconView.widthAnchor.constraint(equalToConstant: 18),
            roleIconView.heightAnchor.constraint(equalToConstant: 18),

            stack.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: roleView.trailingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -8)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with trip: ScheduledTrip, action: TripAction) {
        let time = HomePresentationFormatting.timeFormatter.string(from: trip.scheduledPickupAt)
        let role = HomePresentationFormatting.title(for: trip.assignment)
        roleView.backgroundColor = trip.assignment == .primary ? DriverTheme.brandColor : DriverTheme.accentColor
        roleIconView.image = UIImage(systemName: trip.assignment == .primary ? "checkmark" : "exclamationmark")
        titleLabel.text = "\(time) · \(trip.pickupName)"
        detailLabel.text = "\(role) to \(trip.dropoffName)"
        actionLabel.text = HomePresentationFormatting.title(for: action)
        accessibilityLabel = "\(time), \(role), from \(trip.pickupName) to \(trip.dropoffName), \(HomePresentationFormatting.title(for: action))"
    }
}

private extension UIFont {
    func bold() -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(.traitBold) else { return self }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
