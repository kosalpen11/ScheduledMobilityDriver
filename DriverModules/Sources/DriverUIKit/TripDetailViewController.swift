//
//  TripDetailViewController.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/5/26.
//

import Combine
import DesignSystem
import DriverDomain
import DriverPresentation
import FeatureContracts
import MapKit
import UIKit

final class TripDetailViewController: UIViewController {
    private let model: TripDetailViewModel
    private let onOutput: (TripOutput) -> Void
    private var cancellables = Set<AnyCancellable>()

    private let mapView = MKMapView()
    private let panelView = UIStackView()
    private let statusLabel = UILabel()
    private let routeLabel = UILabel()
    private let pickupLabel = UILabel()
    private let dropoffLabel = UILabel()
    private let notesLabel = UILabel()
    private let messageLabel = UILabel()
    private let primaryButton = UIButton(type: .system)
    private let reconnectingIndicator = DriverReconnectingIndicatorView()

    init(model: TripDetailViewModel, onOutput: @escaping (TripOutput) -> Void) {
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
        title = "Trip"
        view.backgroundColor = .systemBackground
        configureMap()
        configurePanel()
        bind()
        Task { await model.load() }
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
    }

    private func configurePanel() {
        panelView.translatesAutoresizingMaskIntoConstraints = false
        panelView.axis = .vertical
        panelView.spacing = 14
        panelView.layoutMargins = UIEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        panelView.isLayoutMarginsRelativeArrangement = true
        panelView.backgroundColor = DriverTheme.panelColor
        panelView.layer.cornerRadius = DriverTheme.cornerRadius + 4
        panelView.layer.cornerCurve = .continuous
        panelView.layer.shadowColor = UIColor.black.cgColor
        panelView.layer.shadowOpacity = 0.16
        panelView.layer.shadowRadius = 22
        panelView.layer.shadowOffset = CGSize(width: 0, height: 10)
        view.addSubview(panelView)

        let grabber = UIView()
        grabber.translatesAutoresizingMaskIntoConstraints = false
        grabber.backgroundColor = .tertiaryLabel
        grabber.layer.cornerRadius = 2
        grabber.heightAnchor.constraint(equalToConstant: 4).isActive = true
        grabber.widthAnchor.constraint(equalToConstant: 38).isActive = true
        let grabberWrap = UIStackView(arrangedSubviews: [grabber])
        grabberWrap.alignment = .center

        statusLabel.font = .preferredFont(forTextStyle: .caption1)
        statusLabel.textColor = .secondaryLabel
        routeLabel.font = .preferredFont(forTextStyle: .title2).bold()
        pickupLabel.font = .preferredFont(forTextStyle: .body)
        dropoffLabel.font = .preferredFont(forTextStyle: .body)
        notesLabel.font = .preferredFont(forTextStyle: .subheadline)
        notesLabel.textColor = .secondaryLabel
        messageLabel.font = .preferredFont(forTextStyle: .subheadline)
        messageLabel.textColor = DriverTheme.destructiveColor

        [statusLabel, routeLabel, pickupLabel, dropoffLabel, notesLabel, messageLabel].forEach {
            $0.adjustsFontForContentSizeCategory = true
            $0.numberOfLines = 0
        }

        primaryButton.configuration = .filled()
        primaryButton.configuration?.cornerStyle = .medium
        primaryButton.configuration?.baseBackgroundColor = DriverTheme.brandColor
        primaryButton.configuration?.baseForegroundColor = .white
        primaryButton.addTarget(self, action: #selector(primaryTapped), for: .touchUpInside)
        primaryButton.heightAnchor.constraint(greaterThanOrEqualToConstant: DriverTheme.controlHeight).isActive = true

        panelView.addArrangedSubview(grabberWrap)
        panelView.addArrangedSubview(statusLabel)
        panelView.addArrangedSubview(routeLabel)
        panelView.addArrangedSubview(makeInfoCard(title: "Pickup", label: pickupLabel))
        panelView.addArrangedSubview(makeInfoCard(title: "Destination", label: dropoffLabel))
        panelView.addArrangedSubview(notesLabel)
        panelView.addArrangedSubview(messageLabel)
        panelView.addArrangedSubview(reconnectingIndicator)
        panelView.addArrangedSubview(primaryButton)

        NSLayoutConstraint.activate([
            panelView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: DriverTheme.outerMargin),
            panelView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -DriverTheme.outerMargin),
            panelView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -DriverTheme.outerMargin),
            panelView.heightAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.heightAnchor, multiplier: 0.68)
        ])
    }

    private func makeInfoCard(title: String, label: UILabel) -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .preferredFont(forTextStyle: .caption1)
        titleLabel.textColor = .secondaryLabel
        titleLabel.adjustsFontForContentSizeCategory = true
        let stack = UIStackView(arrangedSubviews: [titleLabel, label])
        stack.axis = .vertical
        stack.spacing = 5
        stack.layoutMargins = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        stack.isLayoutMarginsRelativeArrangement = true
        stack.backgroundColor = DriverTheme.cardColor
        stack.layer.cornerRadius = DriverTheme.cardCornerRadius
        stack.layer.cornerCurve = .continuous
        stack.isAccessibilityElement = true
        stack.accessibilityLabel = "\(title), \(label.text ?? "")"
        return stack
    }

    private func bind() {
        model.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.render(state) }
            .store(in: &cancellables)
    }

    private func render(_ state: TripDetailViewModel.State) {
        reconnectingIndicator.setVisible(isRefreshingContent(state))

        guard let presentation = state.presentation else {
            statusLabel.text = "Loading"
            routeLabel.text = "Scheduled trip"
            pickupLabel.text = "--"
            dropoffLabel.text = "--"
            notesLabel.text = nil
            messageLabel.text = failureMessage(from: state)
            primaryButton.configuration?.title = "Loading"
            primaryButton.isEnabled = false
            return
        }

        let trip = presentation.trip
        let time = HomePresentationFormatting.timeFormatter.string(from: trip.scheduledPickupAt)
        statusLabel.text = "\(HomePresentationFormatting.title(for: trip.assignment)) · \(HomePresentationFormatting.title(for: trip.status)) · \(time)"
        routeLabel.text = "\(trip.pickupName) to \(trip.dropoffName)"
        pickupLabel.text = "\(trip.pickupName)\n\(trip.pickupAddress)"
        dropoffLabel.text = "\(trip.dropoffName)\n\(trip.dropoffAddress)"
        notesLabel.text = trip.passengerNote.map { "Passenger note: \($0)" } ?? "No passenger notes."
        messageLabel.text = recoverableMessage(from: state)
        let title = HomePresentationFormatting.title(for: presentation.primaryAction)
        let isActionLoading: Bool
        if case .actionInFlight = state {
            isActionLoading = true
        } else {
            isActionLoading = false
        }
        primaryButton.setDriverLoading(isActionLoading, title: title)
        primaryButton.isEnabled = presentation.canPerformPrimaryAction && !state.isBusy
        primaryButton.alpha = primaryButton.isEnabled ? 1 : 0.5
        renderMap(for: trip)
    }

    private func isRefreshingContent(_ state: TripDetailViewModel.State) -> Bool {
        if case .refreshing = state, state.presentation != nil {
            return true
        }
        return false
    }

    private func renderMap(for trip: ScheduledTrip) {
        mapView.removeAnnotations(mapView.annotations)
        let pickup = MKPointAnnotation()
        pickup.title = "Pickup"
        pickup.subtitle = trip.pickupName
        pickup.coordinate = CLLocationCoordinate2D(latitude: trip.pickupCoordinate.latitude, longitude: trip.pickupCoordinate.longitude)
        let dropoff = MKPointAnnotation()
        dropoff.title = "Destination"
        dropoff.subtitle = trip.dropoffName
        dropoff.coordinate = CLLocationCoordinate2D(latitude: trip.dropoffCoordinate.latitude, longitude: trip.dropoffCoordinate.longitude)
        mapView.addAnnotations([pickup, dropoff])
        mapView.showAnnotations([pickup, dropoff], animated: false)
    }

    private func recoverableMessage(from state: TripDetailViewModel.State) -> String? {
        if case .recoverableError(_, let message) = state {
            return message
        }
        return nil
    }

    private func failureMessage(from state: TripDetailViewModel.State) -> String? {
        if case .failure(let message) = state {
            return message
        }
        return nil
    }

    @objc private func primaryTapped() {
        if UIAccessibility.isReduceMotionEnabled == false {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        Task { [weak self] in
            guard let self else { return }
            let changed = await model.performPrimaryAction()
            if changed {
                onOutput(.tripChanged)
            }
        }
    }
}

private extension UIFont {
    func bold() -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(.traitBold) else { return self }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
