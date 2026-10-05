//
//  DriverProfileViewController.swift
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
import UniformTypeIdentifiers

final class DriverProfileViewController: UIViewController {
    private let model: DriverProfileViewModel
    private let onOutput: (DriverProfileOutput) -> Void
    private var cancellables = Set<AnyCancellable>()
    private var currentSummary: DriverProfileSummary?
    private var pendingUploadType: DriverDocumentType?
    private var pendingExpiry: Date?

    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private let activity = UIActivityIndicatorView(style: .large)
    private let messageLabel = UILabel()

    init(model: DriverProfileViewModel, onOutput: @escaping (DriverProfileOutput) -> Void) {
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
        title = "Profile"
        view.backgroundColor = .systemBackground
        configureLayout()
        bindModel()
        Task { await model.load() }
    }

    private func configureLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        stackView.translatesAutoresizingMaskIntoConstraints = false
        activity.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.translatesAutoresizingMaskIntoConstraints = false

        stackView.axis = .vertical
        stackView.spacing = DriverTheme.innerMargin
        stackView.layoutMargins = UIEdgeInsets(
            top: DriverTheme.outerMargin,
            left: DriverTheme.outerMargin,
            bottom: DriverTheme.outerMargin,
            right: DriverTheme.outerMargin
        )
        stackView.isLayoutMarginsRelativeArrangement = true

        messageLabel.font = .preferredFont(forTextStyle: .body)
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.textColor = .secondaryLabel
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0

        view.addSubview(scrollView)
        view.addSubview(activity)
        scrollView.addSubview(stackView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            activity.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activity.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func bindModel() {
        model.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.render(state: state) }
            .store(in: &cancellables)

        model.$isSubmitting
            .combineLatest(model.$isUploading)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] submitting, uploading in
                submitting || uploading ? self?.activity.startAnimating() : self?.activity.stopAnimating()
            }
            .store(in: &cancellables)

        model.$message
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in self?.showMessage(message) }
            .store(in: &cancellables)
    }

    private func render(state: DriverProfileViewModel.State) {
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        switch state {
        case .idle, .loading:
            activity.startAnimating()
        case .failed(let message):
            activity.stopAnimating()
            let card = makeCard()
            let title = makeLabel("Unable to load profile", style: .title3, weight: .bold)
            let detail = makeSecondaryLabel(message)
            let retry = makePrimaryButton("Retry", action: #selector(retryTapped))
            add([title, detail, retry], to: card)
            stackView.addArrangedSubview(card)
        case .loaded(let summary):
            activity.stopAnimating()
            currentSummary = summary
            stackView.addArrangedSubview(makeIdentityCard(summary))
            stackView.addArrangedSubview(makeNextActionCard(summary))
            stackView.addArrangedSubview(makeDocumentsCard(summary))
            stackView.addArrangedSubview(makeVehicleCard(summary))
            stackView.addArrangedSubview(makeHelpAccountCard(summary))
        }
    }

    private func makeIdentityCard(_ summary: DriverProfileSummary) -> UIView {
        let card = makeCard()
        add([makeSectionTitle("Driver identity")], to: card)
        let name = makeLabel(summary.fullName, style: .largeTitle, weight: .bold)
        let phone = makeSecondaryLabel(summary.maskedPhone)
        let status = makeStatusRow(title: summary.statusTitle, detail: summary.statusDetail, iconName: summary.statusIconName, color: summary.canOperate ? DriverTheme.brandColor : .systemOrange)
        add([name, phone, status], to: card)
        return card
    }

    private func makeNextActionCard(_ summary: DriverProfileSummary) -> UIView {
        let card = makeCard()
        add([makeSectionTitle("What you need to do")], to: card)
        let detail = makeSecondaryLabel(summary.primaryAction.detail)
        switch summary.primaryAction.kind {
        case .submitApplication:
            let button = makePrimaryButton(summary.primaryAction.title, action: #selector(submitTapped))
            add([detail, button], to: card)
        case .openDocument(let type):
            let button = makeSecondaryButton(summary.primaryAction.title) { [weak self] in
                self?.openDocumentDetails(type)
            }
            add([detail, button], to: card)
        case .none:
            add([detail], to: card)
        }
        return card
    }

    private func makeVehicleCard(_ summary: DriverProfileSummary) -> UIView {
        let card = makeCard()
        add([makeSectionTitle("Your vehicle")], to: card)
        if let vehicle = summary.vehicle {
            add([makeRow(title: summary.vehicleTitle, subtitle: summary.vehicleDetail, trailing: vehicle.status.displayTitle, state: vehicle.status == .active ? .approved : .pending)], to: card)
        } else {
            add([makeLabel(summary.vehicleTitle, style: .body, weight: .semibold), makeSecondaryLabel(summary.vehicleDetail)], to: card)
        }
        return card
    }

    private func makeDocumentsCard(_ summary: DriverProfileSummary) -> UIView {
        let card = makeCard()
        add([makeSectionTitle("Your documents")], to: card)
        for row in summary.documents {
            add([makeDocumentRowButton(row)], to: card)
        }
        return card
    }

    private func makeHelpAccountCard(_ summary: DriverProfileSummary) -> UIView {
        let card = makeCard()
        add([makeSectionTitle("Help and account")], to: card)
        if summary.supportOptions.isEmpty {
            add([makeSecondaryLabel("Support contact details are not configured in this app yet. Use your operator's normal support channel.")], to: card)
        } else {
            for option in summary.supportOptions {
                add([makeRow(title: option.title, subtitle: option.detail, trailing: "", state: .pending)], to: card)
            }
        }
        let signOut = makeSecondaryButton("Sign out") { [weak self] in
            self?.logoutTapped()
        }
        add([signOut], to: card)
        return card
    }

    private func makeDocumentRowButton(_ row: DriverDocumentRow) -> UIButton {
        let button = ActionButton { [weak self] in
            self?.openDocumentDetails(row.type)
        }
        button.configuration = .plain()
        button.configuration?.contentInsets = .zero
        button.accessibilityLabel = "\(row.title), \(row.subtitle), \(row.status.title). Opens document details."
        let content = makeRow(title: row.title, subtitle: row.subtitle, trailing: row.status.title, state: row.status)
        content.translatesAutoresizingMaskIntoConstraints = false
        content.isUserInteractionEnabled = false
        button.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            content.topAnchor.constraint(equalTo: button.topAnchor),
            content.bottomAnchor.constraint(equalTo: button.bottomAnchor),
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: DriverTheme.minimumTouchTarget)
        ])
        return button
    }

    private func openDocumentDetails(_ type: DriverDocumentType) {
        guard let row = currentSummary?.documents.first(where: { $0.type == type }) else { return }
        var message = "\(row.status.title)\n\(row.subtitle)"
        if let reason = row.rejectionReason {
            message += "\n\nReason: \(reason)"
        }
        if let expiry = row.expiresOn {
            message += "\nExpires: \(expiry)"
        }
        let alert = UIAlertController(title: row.title, message: message, preferredStyle: .alert)
        if row.canUpload {
            alert.addAction(UIAlertAction(title: row.actionTitle, style: .default) { [weak self] _ in
                self?.chooseDocument(for: type)
            })
        }
        alert.addAction(UIAlertAction(title: "Close", style: .cancel))
        present(alert, animated: true)
    }

    private func chooseDocument(for type: DriverDocumentType) {
        if UIAccessibility.isReduceMotionEnabled == false {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        if type.requiresExpiry {
            promptForExpiry(type: type)
        } else {
            presentPicker(type: type, expiry: nil)
        }
    }

    private func promptForExpiry(type: DriverDocumentType) {
        let alert = UIAlertController(title: "Expiry date", message: "Use YYYY-MM-DD.", preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "2028-12-31"
            field.keyboardType = .numbersAndPunctuation
            field.textContentType = .none
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Continue", style: .default) { [weak self, weak alert] _ in
            guard let text = alert?.textFields?.first?.text, let date = Self.date(from: text) else {
                self?.showMessage("Enter expiry as YYYY-MM-DD.")
                return
            }
            self?.presentPicker(type: type, expiry: date)
        })
        present(alert, animated: true)
    }

    private func presentPicker(type: DriverDocumentType, expiry: Date?) {
        pendingUploadType = type
        pendingExpiry = expiry
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.jpeg, .png, .pdf], asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    private func confirmUpload(type: DriverDocumentType, url: URL, data: Data) {
        let size = ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
        let alert = UIAlertController(title: type.displayTitle, message: "Selected file:\n\(url.lastPathComponent)\n\(size)", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Upload", style: .default) { [weak self] _ in
            guard let self else { return }
            let vehicleID = type.isVehicleDocument ? self.currentSummary?.vehicle?.id : nil
            let upload = DriverDocumentUpload(
                type: type,
                vehicleID: vehicleID,
                expiresOn: self.pendingExpiry,
                filename: url.lastPathComponent,
                content: data
            )
            Task { await self.model.upload(upload) }
        })
        present(alert, animated: true)
    }

    private func makeCard() -> UIStackView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.layoutMargins = UIEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        stack.isLayoutMarginsRelativeArrangement = true
        stack.backgroundColor = DriverTheme.cardColor
        stack.layer.cornerRadius = DriverTheme.cardCornerRadius
        stack.layer.cornerCurve = .continuous
        return stack
    }

    private func makeStatusRow(title: String, detail: String, iconName: String, color: UIColor) -> UIView {
        let icon = UIImageView(image: UIImage(systemName: iconName))
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.tintColor = color
        icon.contentMode = .scaleAspectFit
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 28),
            icon.heightAnchor.constraint(equalToConstant: 28)
        ])

        let titleLabel = makeLabel(title, style: .headline, weight: .bold)
        let detailLabel = makeSecondaryLabel(detail)
        let textStack = UIStackView(arrangedSubviews: [titleLabel, detailLabel])
        textStack.axis = .vertical
        textStack.spacing = 4

        let row = UIStackView(arrangedSubviews: [icon, textStack])
        row.axis = .horizontal
        row.alignment = .top
        row.spacing = 12
        row.isAccessibilityElement = true
        row.accessibilityLabel = "\(title). \(detail)"
        return row
    }

    private func makeLabel(_ text: String, style: UIFont.TextStyle, weight: UIFont.Weight) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: UIFont.preferredFont(forTextStyle: style).pointSize, weight: weight)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        return label
    }

    private func makeSecondaryLabel(_ text: String) -> UILabel {
        let label = makeLabel(text, style: .body, weight: .regular)
        label.textColor = .secondaryLabel
        return label
    }

    private func makeSectionTitle(_ text: String) -> UILabel {
        makeLabel(text, style: .title3, weight: .bold)
    }

    private func makePill(_ text: String, color: UIColor) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = color
        label.backgroundColor = color.withAlphaComponent(0.12)
        label.layer.cornerRadius = 8
        label.layer.masksToBounds = true
        label.textAlignment = .center
        label.heightAnchor.constraint(greaterThanOrEqualToConstant: 32).isActive = true
        return label
    }

    private func makeRow(title: String, subtitle: String, trailing: String, state: DriverChecklistState) -> UIView {
        let titleLabel = makeLabel(title, style: .body, weight: .semibold)
        let subtitleLabel = makeSecondaryLabel(subtitle)
        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.spacing = 4
        let pill = makePill(trailing, color: color(for: state))
        let row = UIStackView(arrangedSubviews: [textStack, pill])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        textStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        pill.setContentHuggingPriority(.required, for: .horizontal)
        row.isAccessibilityElement = true
        row.accessibilityLabel = "\(title), \(subtitle), \(trailing)"
        return row
    }

    private func makePrimaryButton(_ title: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.configuration = .filled()
        button.configuration?.title = title
        button.configuration?.baseBackgroundColor = DriverTheme.accentColor
        button.configuration?.cornerStyle = .medium
        button.addTarget(self, action: action, for: .touchUpInside)
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: DriverTheme.minimumTouchTarget).isActive = true
        return button
    }

    private func makeSecondaryButton(_ title: String, action: @escaping () -> Void) -> UIButton {
        let button = ActionButton(action: action)
        button.configuration = .bordered()
        button.configuration?.title = title
        button.configuration?.cornerStyle = .medium
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: DriverTheme.minimumTouchTarget).isActive = true
        return button
    }

    private func add(_ views: [UIView], to stack: UIStackView) {
        views.forEach { stack.addArrangedSubview($0) }
    }

    private func color(for state: DriverChecklistState) -> UIColor {
        switch state {
        case .approved:
            return .systemGreen
        case .pending:
            return .systemOrange
        case .rejected, .expired:
            return DriverTheme.destructiveColor
        case .missing:
            return .secondaryLabel
        }
    }

    private func showMessage(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.model.dismissMessage()
        })
        present(alert, animated: true)
    }

    @objc private func retryTapped() {
        Task { await model.load() }
    }

    @objc private func submitTapped() {
        if UIAccessibility.isReduceMotionEnabled == false {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        Task { await model.submit() }
    }

    @objc private func logoutTapped() {
        onOutput(.logoutRequested)
    }

    private static func date(from string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: string)
    }
}

extension DriverProfileViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let type = pendingUploadType, let url = urls.first else { return }
        let didStart = url.startAccessingSecurityScopedResource()
        defer {
            if didStart { url.stopAccessingSecurityScopedResource() }
        }
        do {
            let data = try Data(contentsOf: url)
            confirmUpload(type: type, url: url, data: data)
        } catch {
            showMessage("The selected file could not be read.")
        }
    }
}

private final class ActionButton: UIButton {
    private let actionHandler: () -> Void

    init(action: @escaping () -> Void) {
        self.actionHandler = action
        super.init(frame: .zero)
        addTarget(self, action: #selector(trigger), for: .touchUpInside)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func trigger() {
        actionHandler()
    }
}

private extension DriverVehicleStatus {
    var displayTitle: String {
        switch self {
        case .active:
            return "Active"
        case .inactive:
            return "Inactive"
        case .unknown:
            return "Unknown"
        }
    }
}
