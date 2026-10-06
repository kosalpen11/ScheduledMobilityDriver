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
import PhotosUI
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
        view.backgroundColor = .systemGroupedBackground
        configureLayout()
        bindModel()
        Task { await model.load() }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    private func configureLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        stackView.translatesAutoresizingMaskIntoConstraints = false
        activity.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.translatesAutoresizingMaskIntoConstraints = false

        stackView.axis = .vertical
        stackView.spacing = 14
        stackView.layoutMargins = UIEdgeInsets(
            top: 12,
            left: DriverTheme.outerMargin,
            bottom: DriverTheme.outerMargin + 12,
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
            stackView.addArrangedSubview(makeIdentityHeader(summary))
            stackView.addArrangedSubview(makeSectionCard(title: "Next step", body: makeNextStepContent(summary)))
            stackView.addArrangedSubview(makeSectionCard(title: "Documents", body: makeDocumentsOverview(summary)))
            stackView.addArrangedSubview(makeSectionCard(title: "Vehicle", body: makeVehicleOverview(summary)))
            stackView.addArrangedSubview(makeSectionCard(title: "Help", body: makeHelpContent(summary)))
            stackView.addArrangedSubview(makeSectionCard(title: "Account", body: makeAccountContent()))
        }
    }

    private func makeIdentityHeader(_ summary: DriverProfileSummary) -> UIView {
        let card = makeCard(padding: 18)
        card.spacing = 14

        let initials = makeInitialsBadge(name: summary.fullName, color: summary.canOperate ? DriverTheme.brandColor : .systemOrange)
        let name = makeLabel(summary.fullName, style: .title2, weight: .bold)
        let phone = makeSecondaryLabel(summary.maskedPhone)
        let nameStack = UIStackView(arrangedSubviews: [name, phone])
        nameStack.axis = .vertical
        nameStack.spacing = 2

        let header = UIStackView(arrangedSubviews: [initials, nameStack])
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = 12
        nameStack.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let status = makeStatusBanner(
            title: summary.statusTitle,
            detail: summary.statusDetail,
            iconName: summary.statusIconName,
            color: summary.canOperate ? DriverTheme.brandColor : .systemOrange
        )
        add([header, status], to: card)
        return card
    }

    private func makeNextStepContent(_ summary: DriverProfileSummary) -> UIView {
        let stack = makePlainStack()
        let detail = makeSecondaryLabel(summary.primaryAction.detail)
        switch summary.primaryAction.kind {
        case .submitApplication:
            let button = makePrimaryButton(summary.primaryAction.title, action: #selector(submitTapped))
            add([detail, button], to: stack)
        case .openDocument(let type):
            let button = makePrimaryActionButton(summary.primaryAction.title) { [weak self] in
                self?.openDocumentDetails(type)
            }
            add([detail, button], to: stack)
        case .none:
            add([detail], to: stack)
        }
        return stack
    }

    private func makeVehicleOverview(_ summary: DriverProfileSummary) -> UIView {
        let stack = makePlainStack()
        if let vehicle = summary.vehicle {
            let state: DriverChecklistState = vehicle.status == .active ? .approved : .pending
            add([makeSimpleRow(iconName: "car.fill", title: summary.vehicleTitle, subtitle: summary.vehicleDetail, trailing: vehicle.status.displayTitle, state: state, showsDisclosure: false)], to: stack)
        } else {
            add([makeSimpleRow(iconName: "car", title: summary.vehicleTitle, subtitle: summary.vehicleDetail, trailing: nil, state: .missing, showsDisclosure: false)], to: stack)
        }
        return stack
    }

    private func makeDocumentsOverview(_ summary: DriverProfileSummary) -> UIView {
        let stack = makePlainStack()
        let progress = makeDocumentProgress(summary)
        add([progress, makeDocumentGroupTitle("Driver documents")], to: stack)
        for row in summary.driverDocuments {
            add([makeDocumentRowButton(row)], to: stack)
        }
        if summary.hasVehicleDocumentRequirements {
            add([makeDocumentGroupTitle("Vehicle documents")], to: stack)
            for row in summary.vehicleDocuments {
                add([makeDocumentRowButton(row)], to: stack)
            }
        }
        return stack
    }

    private func makeHelpContent(_ summary: DriverProfileSummary) -> UIView {
        let stack = makePlainStack()
        if summary.supportOptions.isEmpty {
            add([makeSecondaryLabel("Support contact details are not configured in this app yet. Use your operator's normal support channel.")], to: stack)
        } else {
            for option in summary.supportOptions {
                add([makeSimpleRow(iconName: "questionmark.circle", title: option.title, subtitle: option.detail, trailing: nil, state: .pending, showsDisclosure: false)], to: stack)
            }
        }
        return stack
    }

    private func makeAccountContent() -> UIView {
        let stack = makePlainStack()
        let signOut = makeSecondaryButton("Sign out") { [weak self] in
            self?.logoutTapped()
        }
        add([signOut], to: stack)
        return stack
    }

    private func makeDocumentRowButton(_ row: DriverDocumentRow) -> UIButton {
        let button = ActionButton { [weak self] in
            self?.openDocumentDetails(row.type)
        }
        button.configuration = .plain()
        button.configuration?.contentInsets = .zero
        button.accessibilityLabel = "\(row.title), \(row.status.title). \(row.subtitle). Opens document details."
        let rowView = makeSimpleRow(
            iconName: iconName(for: row.type),
            title: row.title,
            subtitle: row.subtitle,
            trailing: row.status.title,
            state: row.status,
            showsDisclosure: true
        )
        let content = paddedRowContainer(rowView, state: row.status, isActionable: row.canUpload)
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
        if type == .nationalID {
            chooseDocument(for: type)
            return
        }
        guard let row = currentSummary?.documents.first(where: { $0.type == type }) else { return }
        let detail = DriverDocumentDetailViewController(row: row) { [weak self] in
            self?.chooseDocument(for: type)
        }
        navigationController?.pushViewController(detail, animated: true)
    }

    private func chooseDocument(for type: DriverDocumentType) {
        if UIAccessibility.isReduceMotionEnabled == false {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        if type == .nationalID {
            pendingUploadType = type
            pendingExpiry = nil
            presentCamera(for: type)
            return
        }
        if type.requiresExpiry && type != .nationalID {
            promptForExpiry(type: type)
        } else {
            presentUploadSourceOptions(type: type, expiry: nil)
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
            self?.presentUploadSourceOptions(type: type, expiry: date)
        })
        presentOnTop(alert)
    }

    private func presentUploadSourceOptions(type: DriverDocumentType, expiry: Date?) {
        pendingUploadType = type
        pendingExpiry = expiry
        let sheet = UIAlertController(title: type.displayTitle, message: "Choose how to add this document.", preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Photo library", style: .default) { [weak self] _ in
            self?.presentPhotoPicker()
        })
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            sheet.addAction(UIAlertAction(title: "Camera", style: .default) { [weak self] _ in
                self?.presentCamera(for: type)
            })
        }
        if type != .profilePhoto {
            sheet.addAction(UIAlertAction(title: "Files", style: .default) { [weak self] _ in
                self?.presentFilePicker(for: type)
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        sheet.popoverPresentationController?.sourceView = view
        sheet.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        presentOnTop(sheet)
    }

    private func presentPhotoPicker() {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        presentOnTop(picker)
    }

    private func presentCamera(for type: DriverDocumentType) {
        if type == .nationalID {
            pendingUploadType = type
            pendingExpiry = nil
            let controller = NationalIDCameraViewController { [weak self] capture in
                self?.processNationalIDImage(
                    capture.image,
                    filename: Self.photoFilename(for: type),
                    expectedStillQuad: capture.expectedStillQuad
                )
            } onCancel: {
            } onPhotoLibrary: { [weak self] in
                self?.pendingUploadType = type
                self?.pendingExpiry = nil
                self?.presentPhotoPicker()
            } onFiles: { [weak self] in
                self?.pendingUploadType = type
                self?.pendingExpiry = nil
                self?.presentFilePicker(for: type)
            }
            presentOnTop(controller)
            return
        }
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.image.identifier]
        picker.delegate = self
        presentOnTop(picker)
    }

    private func presentFilePicker(for type: DriverDocumentType) {
        pendingUploadType = type
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.jpeg, .png, .pdf], asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        presentOnTop(picker)
    }

    private func confirmUpload(type: DriverDocumentType, filename: String, data: Data, previewImage: UIImage? = nil, onRetake: (() -> Void)? = nil) {
        let size = ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
        let preview = DocumentUploadPreviewViewController(
            documentTitle: type.displayTitle,
            filename: filename,
            fileSize: size,
            previewImage: previewImage,
            onRetake: onRetake
        ) { [weak self] controller in
            controller.dismiss(animated: true)
            guard let self else { return }
            let vehicleID = type.isVehicleDocument ? self.currentSummary?.vehicle?.id : nil
            let upload = DriverDocumentUpload(
                type: type,
                vehicleID: vehicleID,
                expiresOn: self.pendingExpiry,
                filename: filename,
                content: data
            )
            Task { await self.model.upload(upload) }
        }
        let navigation = UINavigationController(rootViewController: preview)
        navigation.modalPresentationStyle = .pageSheet
        presentOnTop(navigation)
    }

    private func processNationalIDImage(
        _ image: UIImage,
        filename: String,
        expectedStillQuad: NationalIDQuad? = nil
    ) {
        activity.startAnimating()
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try NationalIDVisionProcessor.process(
                        image: image,
                        fallbackFilename: filename,
                        expectedStillQuad: expectedStillQuad
                    )
                }.value
                activity.stopAnimating()
                pendingExpiry = result.expiryDate
                if result.expiryDate == nil {
                    promptForExpiryBeforeConfirmingNationalID(result)
                } else {
                    confirmUpload(type: .nationalID, filename: result.filename, data: result.imageData, previewImage: result.previewImage) { [weak self] in
                        self?.presentCamera(for: .nationalID)
                    }
                }
            } catch let failure as NationalIDVisionFailure {
                activity.stopAnimating()
                showMessage(failure.message)
            } catch {
                activity.stopAnimating()
                showMessage("The National ID photo could not be processed.")
            }
        }
    }

    private func promptForExpiryBeforeConfirmingNationalID(_ result: NationalIDVisionResult) {
        let alert = UIAlertController(title: "Expiry date", message: "We could not read the expiry date from the MRZ. Enter it as YYYY-MM-DD.", preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "2028-12-31"
            field.keyboardType = .numbersAndPunctuation
            field.textContentType = .none
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Continue", style: .default) { [weak self, weak alert] _ in
            guard let self else { return }
            guard let text = alert?.textFields?.first?.text, let date = Self.date(from: text) else {
                self.showMessage("Enter expiry as YYYY-MM-DD.")
                return
            }
            self.pendingExpiry = date
            self.confirmUpload(type: .nationalID, filename: result.filename, data: result.imageData, previewImage: result.previewImage) { [weak self] in
                self?.presentCamera(for: .nationalID)
            }
        })
        presentOnTop(alert)
    }

    private func makeSectionCard(title: String, body: UIView) -> UIView {
        let card = makeCard(padding: 16)
        let header = makeSectionHeader(title)
        add([header, body], to: card)
        return card
    }

    private func makePlainStack() -> UIStackView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        return stack
    }

    private func makeCard(padding: CGFloat = 18) -> UIStackView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.layoutMargins = UIEdgeInsets(top: padding, left: padding, bottom: padding, right: padding)
        stack.isLayoutMarginsRelativeArrangement = true
        stack.backgroundColor = DriverTheme.cardColor
        stack.layer.cornerRadius = DriverTheme.cardCornerRadius
        stack.layer.cornerCurve = .continuous
        stack.layer.borderWidth = 1
        stack.layer.borderColor = DriverTheme.separatorColor.cgColor
        return stack
    }

    private func makeInitialsBadge(name: String, color: UIColor) -> UIView {
        let label = UILabel()
        let initials = name
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
            .uppercased()
        label.text = initials.isEmpty ? "D" : initials
        label.font = .systemFont(ofSize: 20, weight: .bold)
        label.textColor = color
        label.textAlignment = .center
        label.backgroundColor = color.withAlphaComponent(0.14)
        label.layer.cornerRadius = 24
        label.layer.masksToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.widthAnchor.constraint(equalToConstant: 48),
            label.heightAnchor.constraint(equalToConstant: 48)
        ])
        return label
    }

    private func makeStatusBanner(title: String, detail: String, iconName: String, color: UIColor) -> UIView {
        let icon = UIImageView(image: UIImage(systemName: iconName))
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.tintColor = color
        icon.contentMode = .scaleAspectFit
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 22),
            icon.heightAnchor.constraint(equalToConstant: 22)
        ])

        let titleLabel = makeLabel(title, style: .headline, weight: .bold)
        titleLabel.textColor = color
        let detailLabel = makeSecondaryLabel(detail)
        detailLabel.font = .preferredFont(forTextStyle: .subheadline)

        let textStack = UIStackView(arrangedSubviews: [titleLabel, detailLabel])
        textStack.axis = .vertical
        textStack.spacing = 3

        let row = UIStackView(arrangedSubviews: [icon, textStack])
        row.axis = .horizontal
        row.alignment = .top
        row.spacing = 10
        row.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
        row.isLayoutMarginsRelativeArrangement = true
        row.backgroundColor = color.withAlphaComponent(0.10)
        row.layer.cornerRadius = 8
        row.layer.cornerCurve = .continuous
        row.isAccessibilityElement = true
        row.accessibilityLabel = "\(title). \(detail)"
        return row
    }

    private func makeSectionHeader(_ title: String) -> UIView {
        let titleLabel = makeSectionTitle(title)
        let rule = UIView()
        rule.backgroundColor = DriverTheme.separatorColor
        rule.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            rule.heightAnchor.constraint(equalToConstant: 1)
        ])

        let stack = UIStackView(arrangedSubviews: [titleLabel, rule])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 12
        rule.setContentHuggingPriority(.defaultLow, for: .horizontal)
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        return stack
    }

    private func makeDocumentProgress(_ summary: DriverProfileSummary) -> UIView {
        let approved = summary.documents.filter { $0.status == .approved }.count
        let required = max(1, summary.documents.count)
        let progress = Float(approved) / Float(required)

        let text = makeSecondaryLabel(summary.documentProgressText)
        let bar = UIProgressView(progressViewStyle: .default)
        bar.progress = progress
        bar.progressTintColor = progress >= 1 ? DriverTheme.brandColor : DriverTheme.accentColor
        bar.trackTintColor = DriverTheme.separatorColor
        bar.heightAnchor.constraint(equalToConstant: 6).isActive = true

        let stack = UIStackView(arrangedSubviews: [text, bar])
        stack.axis = .vertical
        stack.spacing = 8
        stack.isAccessibilityElement = true
        stack.accessibilityLabel = summary.documentProgressText
        return stack
    }

    private func makeCompactStatusRow(title: String, iconName: String, color: UIColor) -> UIView {
        let icon = UIImageView(image: UIImage(systemName: iconName))
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.tintColor = color
        icon.contentMode = .scaleAspectFit
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 22),
            icon.heightAnchor.constraint(equalToConstant: 22)
        ])

        let titleLabel = makeLabel(title, style: .body, weight: .semibold)
        titleLabel.textColor = color
        let row = UIStackView(arrangedSubviews: [icon, titleLabel])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 8
        row.isAccessibilityElement = true
        row.accessibilityLabel = title
        return row
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
        let label = makeLabel(text, style: .headline, weight: .bold)
        label.textColor = .label
        return label
    }

    private func makeDocumentGroupTitle(_ text: String) -> UILabel {
        let label = makeLabel(text, style: .subheadline, weight: .bold)
        label.textColor = .secondaryLabel
        return label
    }

    private func makePill(_ text: String, color: UIColor) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: UIFont.preferredFont(forTextStyle: .caption1).pointSize, weight: .semibold)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = color
        label.backgroundColor = color.withAlphaComponent(0.12)
        label.layer.cornerRadius = 7
        label.layer.masksToBounds = true
        label.textAlignment = .center
        label.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 5, leading: 8, bottom: 5, trailing: 8)
        label.heightAnchor.constraint(greaterThanOrEqualToConstant: 28).isActive = true
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

    private func makeSimpleRow(
        iconName: String,
        title: String,
        subtitle: String,
        trailing: String?,
        state: DriverChecklistState,
        showsDisclosure: Bool
    ) -> UIView {
        let icon = UIImageView(image: UIImage(systemName: iconName))
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.tintColor = color(for: state)
        icon.contentMode = .scaleAspectFit
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 24),
            icon.heightAnchor.constraint(equalToConstant: 24)
        ])

        let titleLabel = makeLabel(title, style: .body, weight: .semibold)
        let subtitleLabel = makeSecondaryLabel(subtitle)
        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.spacing = 3

        var trailingViews: [UIView] = []
        if let trailing {
            let pill = makePill(trailing, color: color(for: state))
            pill.setContentCompressionResistancePriority(.required, for: .horizontal)
            trailingViews.append(pill)
        }
        if showsDisclosure {
            let configuration = UIImage.SymbolConfiguration(
                pointSize: 13,
                weight: .semibold
            )

            let disclosure = UIImageView(
                image: UIImage(
                    systemName: "chevron.right",
                    withConfiguration: configuration
                )
            )

            disclosure.translatesAutoresizingMaskIntoConstraints = false
            disclosure.tintColor = .tertiaryLabel
            disclosure.contentMode = .scaleAspectFit

            NSLayoutConstraint.activate([
                disclosure.widthAnchor.constraint(equalToConstant: 12),
                disclosure.heightAnchor.constraint(equalToConstant: 18)
            ])

            disclosure.setContentHuggingPriority(.required, for: .horizontal)
            disclosure.setContentCompressionResistancePriority(.required, for: .horizontal)

            trailingViews.append(disclosure)
        }
        let trailingStack = UIStackView(arrangedSubviews: trailingViews)
        trailingStack.axis = .horizontal
        trailingStack.alignment = .center
        trailingStack.spacing = 6

        let row = UIStackView(arrangedSubviews: [icon, textStack, trailingStack])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        textStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        trailingStack.setContentHuggingPriority(.required, for: .horizontal)
        row.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0)
        row.isLayoutMarginsRelativeArrangement = true
        row.isAccessibilityElement = true
        row.accessibilityLabel = [title, trailing, subtitle].compactMap { $0 }.joined(separator: ", ")
        return row
    }

    private func paddedRowContainer(_ content: UIView, state: DriverChecklistState, isActionable: Bool) -> UIView {
        let container = UIView()
        container.backgroundColor = isActionable
            ? color(for: state).withAlphaComponent(0.07)
            : UIColor.secondarySystemGroupedBackground.withAlphaComponent(0.65)
        container.layer.cornerRadius = 8
        container.layer.cornerCurve = .continuous
        container.layer.borderWidth = isActionable ? 1 : 0
        container.layer.borderColor = color(for: state).withAlphaComponent(0.16).cgColor

        content.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            content.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6)
        ])
        return container
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

    private func makePrimaryActionButton(_ title: String, action: @escaping () -> Void) -> UIButton {
        let button = ActionButton(action: action)
        button.configuration = .filled()
        button.configuration?.title = title
        button.configuration?.baseBackgroundColor = DriverTheme.accentColor
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

    private func iconName(for type: DriverDocumentType) -> String {
        switch type {
        case .nationalID:
            return "person.text.rectangle"
        case .drivingLicense:
            return "doc.text"
        case .profilePhoto:
            return "person.crop.circle"
        case .vehicleRegistration:
            return "car.text"
        case .vehicleInsurance:
            return "shield"
        }
    }

    private func showMessage(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.model.dismissMessage()
        })
        presentOnTop(alert)
    }

    private func presentOnTop(_ controller: UIViewController) {
        let presenter = navigationController?.topViewController ?? self
        presenter.present(controller, animated: true)
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

extension DriverProfileViewController: UIDocumentPickerDelegate, PHPickerViewControllerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let type = pendingUploadType, let url = urls.first else { return }
        let didStart = url.startAccessingSecurityScopedResource()
        defer {
            if didStart { url.stopAccessingSecurityScopedResource() }
        }
        do {
            let data = try Data(contentsOf: url)
            if type == .nationalID, let image = UIImage(data: data) {
                processNationalIDImage(image, filename: url.lastPathComponent)
                return
            }
            confirmUpload(type: type, filename: url.lastPathComponent, data: data, previewImage: UIImage(data: data))
        } catch {
            showMessage("The selected file could not be read.")
        }
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let type = pendingUploadType else { return }
        guard let provider = results.first?.itemProvider else { return }
        guard provider.canLoadObject(ofClass: UIImage.self) else {
            showMessage("Choose a JPEG or PNG image.")
            return
        }
        provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                guard let image = object as? UIImage, let data = image.jpegData(compressionQuality: 0.86) else {
                    self.showMessage("The selected photo could not be read.")
                    return
                }
                if type == .nationalID {
                    self.processNationalIDImage(image, filename: Self.photoFilename(for: type))
                    return
                }
                self.confirmUpload(type: type, filename: Self.photoFilename(for: type), data: data, previewImage: image)
            }
        }
    }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)
        guard let type = pendingUploadType else { return }
        guard let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.86) else {
            showMessage("The photo could not be read.")
            return
        }
        if type == .nationalID {
            processNationalIDImage(image, filename: Self.photoFilename(for: type))
            return
        }
        confirmUpload(type: type, filename: Self.photoFilename(for: type), data: data, previewImage: image)
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }

    private static func photoFilename(for type: DriverDocumentType) -> String {
        let safeName = type.displayTitle
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
        return "\(safeName)-photo.jpg"
    }
}

private final class DriverDocumentDetailViewController: UIViewController {
    private let row: DriverDocumentRow
    private let onUpload: () -> Void
    private let stackView = UIStackView()

    init(row: DriverDocumentRow, onUpload: @escaping () -> Void) {
        self.row = row
        self.onUpload = onUpload
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = row.title
        view.backgroundColor = .systemBackground
        configureLayout()
        render()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    private func configureLayout() {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 16
        stackView.layoutMargins = UIEdgeInsets(
            top: DriverTheme.outerMargin,
            left: DriverTheme.outerMargin,
            bottom: DriverTheme.outerMargin,
            right: DriverTheme.outerMargin
        )
        stackView.isLayoutMarginsRelativeArrangement = true

        view.addSubview(scrollView)
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
            stackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])
    }

    private func render() {
        stackView.addArrangedSubview(makeHeader())
        stackView.addArrangedSubview(makeDetailCard())
        stackView.addArrangedSubview(makeSelectionCard())
        if row.canUpload {
            stackView.addArrangedSubview(makeUploadButton())
        }
    }

    private func makeHeader() -> UIView {
        let card = makeCard()
        let icon = UIImageView(image: UIImage(systemName: iconName(for: row.type)))
        icon.tintColor = color(for: row.status)
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 34),
            icon.heightAnchor.constraint(equalToConstant: 34)
        ])

        let title = makeLabel(row.title, style: .title2, weight: .bold)
        let status = makeLabel(row.status.title, style: .headline, weight: .semibold)
        status.textColor = color(for: row.status)
        let text = UIStackView(arrangedSubviews: [title, status])
        text.axis = .vertical
        text.spacing = 4

        let header = UIStackView(arrangedSubviews: [icon, text])
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = 12
        card.addArrangedSubview(header)
        card.addArrangedSubview(makeSecondaryLabel(nextStepText))
        return card
    }

    private func makeDetailCard() -> UIView {
        let card = makeCard()
        card.addArrangedSubview(makeSectionTitle("Details"))
        card.addArrangedSubview(makeKeyValue(title: "Current status", value: row.status.title))
        if let expiresOn = row.expiresOn {
            card.addArrangedSubview(makeKeyValue(title: "Expiry date", value: expiresOn))
        } else if row.type.requiresExpiry {
            card.addArrangedSubview(makeKeyValue(title: "Expiry date", value: "Required when uploading"))
        }
        if let rejectionReason = row.rejectionReason, rejectionReason.isEmpty == false {
            card.addArrangedSubview(makeKeyValue(title: "Reason", value: rejectionReason))
        }
        if row.type.isVehicleDocument {
            card.addArrangedSubview(makeSecondaryLabel("This document will use your assigned vehicle automatically. Vehicle changes are managed by your operator."))
        }
        return card
    }

    private func makeSelectionCard() -> UIView {
        let card = makeCard()
        card.addArrangedSubview(makeSectionTitle("Accepted files"))
        card.addArrangedSubview(makeSecondaryLabel(acceptedFormatText))
        if row.type.requiresExpiry {
            card.addArrangedSubview(makeSecondaryLabel("You will enter the expiry date before selecting the file."))
        }
        card.addArrangedSubview(makeSecondaryLabel("Remote preview is not available because the driver API does not expose document content."))
        return card
    }

    private func makeUploadButton() -> UIView {
        let button = ActionButton { [weak self] in
            if UIAccessibility.isReduceMotionEnabled == false {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            self?.onUpload()
        }
        button.configuration = .filled()
        button.configuration?.title = row.actionTitle == "Upload" ? "Upload document" : "Replace document"
        button.configuration?.baseBackgroundColor = DriverTheme.accentColor
        button.configuration?.cornerStyle = .medium
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: DriverTheme.controlHeight).isActive = true
        return button
    }

    private var nextStepText: String {
        switch row.status {
        case .missing:
            return "Upload this document so your application can move forward."
        case .pending:
            return "No action is needed while this document is under review."
        case .approved:
            return "This document is approved."
        case .rejected:
            return "Replace this document with a clearer or corrected file."
        case .expired:
            return "Replace this document with a current version."
        }
    }

    private var acceptedFormatText: String {
        row.type == .profilePhoto
            ? "Photo library or camera image, uploaded as JPEG, up to 10 MB."
            : "Photo library, camera image, or file upload. JPEG, PNG, or PDF, up to 10 MB."
    }

    private func makeCard() -> UIStackView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.layoutMargins = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.isLayoutMarginsRelativeArrangement = true
        stack.backgroundColor = DriverTheme.cardColor
        stack.layer.cornerRadius = DriverTheme.cardCornerRadius
        stack.layer.cornerCurve = .continuous
        return stack
    }

    private func makeKeyValue(title: String, value: String) -> UIView {
        let titleLabel = makeLabel(title, style: .subheadline, weight: .semibold)
        titleLabel.textColor = .secondaryLabel
        let valueLabel = makeLabel(value, style: .body, weight: .regular)
        let stack = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        stack.axis = .vertical
        stack.spacing = 3
        stack.isAccessibilityElement = true
        stack.accessibilityLabel = "\(title), \(value)"
        return stack
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
        makeLabel(text, style: .headline, weight: .bold)
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

    private func iconName(for type: DriverDocumentType) -> String {
        switch type {
        case .nationalID:
            return "person.text.rectangle"
        case .drivingLicense:
            return "doc.text"
        case .profilePhoto:
            return "person.crop.circle"
        case .vehicleRegistration:
            return "car.text"
        case .vehicleInsurance:
            return "shield"
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

private final class DocumentUploadPreviewViewController: UIViewController {
    private let documentTitle: String
    private let filename: String
    private let fileSize: String
    private let previewImage: UIImage?
    private let onRetake: (() -> Void)?
    private let onUpload: (UIViewController) -> Void

    init(
        documentTitle: String,
        filename: String,
        fileSize: String,
        previewImage: UIImage?,
        onRetake: (() -> Void)? = nil,
        onUpload: @escaping (UIViewController) -> Void
    ) {
        self.documentTitle = documentTitle
        self.filename = filename
        self.fileSize = fileSize
        self.previewImage = previewImage
        self.onRetake = onRetake
        self.onUpload = onUpload
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Preview"
        view.backgroundColor = .systemBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Cancel", style: .plain, target: self, action: #selector(cancelTapped))
        buildLayout()
    }

    private func buildLayout() {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 18

        let titleLabel = makeLabel(documentTitle, style: .title2, weight: .bold)
        let subtitle = makeSecondaryLabel("Check the photo before uploading it for review.")

        let preview = makePreview()
        preview.heightAnchor.constraint(equalToConstant: previewImage == nil ? 150 : 240).isActive = true

        let fileLabel = makeSecondaryLabel("\(filename)\n\(fileSize)")
        fileLabel.textAlignment = .center

        let uploadButton = UIButton(type: .system)
        uploadButton.configuration = .filled()
        uploadButton.configuration?.title = "Upload document"
        uploadButton.configuration?.baseBackgroundColor = DriverTheme.brandColor
        uploadButton.configuration?.baseForegroundColor = .white
        uploadButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        uploadButton.addTarget(self, action: #selector(uploadTapped), for: .touchUpInside)
        uploadButton.heightAnchor.constraint(greaterThanOrEqualToConstant: DriverTheme.minimumTouchTarget).isActive = true

        [titleLabel, subtitle, preview, fileLabel].forEach(stack.addArrangedSubview)
        if onRetake != nil {
            let retakeButton = UIButton(type: .system)
            retakeButton.configuration = .bordered()
            retakeButton.configuration?.title = "Retake photo"
            retakeButton.configuration?.baseForegroundColor = DriverTheme.brandColor
            retakeButton.addTarget(self, action: #selector(retakeTapped), for: .touchUpInside)
            retakeButton.heightAnchor.constraint(greaterThanOrEqualToConstant: DriverTheme.minimumTouchTarget).isActive = true
            stack.addArrangedSubview(retakeButton)
        }
        stack.addArrangedSubview(uploadButton)
        view.addSubview(scrollView)
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24)
        ])
    }

    private func makePreview() -> UIView {
        let container = UIView()
        container.backgroundColor = DriverTheme.cardColor
        container.layer.cornerRadius = DriverTheme.cardCornerRadius
        container.layer.cornerCurve = .continuous
        container.clipsToBounds = true

        if let previewImage {
            let imageView = UIImageView(image: previewImage)
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.contentMode = .scaleAspectFit
            imageView.accessibilityLabel = "\(documentTitle) selected photo preview"
            container.addSubview(imageView)
            NSLayoutConstraint.activate([
                imageView.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
                imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
                imageView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
                imageView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12)
            ])
        } else {
            let icon = UIImageView(image: UIImage(systemName: "doc.fill"))
            icon.translatesAutoresizingMaskIntoConstraints = false
            icon.tintColor = .secondaryLabel
            icon.contentMode = .scaleAspectFit
            container.addSubview(icon)
            NSLayoutConstraint.activate([
                icon.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                icon.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 54),
                icon.heightAnchor.constraint(equalToConstant: 54)
            ])
        }
        return container
    }

    private func makeLabel(_ text: String, style: UIFont.TextStyle, weight: UIFont.Weight) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: UIFont.preferredFont(forTextStyle: style).pointSize, weight: weight)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.textAlignment = .center
        return label
    }

    private func makeSecondaryLabel(_ text: String) -> UILabel {
        let label = makeLabel(text, style: .body, weight: .regular)
        label.textColor = .secondaryLabel
        return label
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    @objc private func uploadTapped() {
        onUpload(self)
    }

    @objc private func retakeTapped() {
        dismiss(animated: true) { [onRetake] in
            onRetake?()
        }
    }
}
