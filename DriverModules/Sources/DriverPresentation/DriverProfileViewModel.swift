//
//  DriverProfileViewModel.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/4/26.
//

import DriverDomain
import Foundation

@MainActor
public final class DriverProfileViewModel: ObservableObject {
    public enum State: Equatable {
        case idle
        case loading
        case loaded(DriverProfileSummary)
        case failed(String)
    }

    @Published public private(set) var state: State = .idle
    @Published public private(set) var isSubmitting = false
    @Published public private(set) var isUploading = false
    @Published public private(set) var message: String?

    private let loadProfile: LoadDriverProfileUseCase
    private let uploadDocument: UploadDriverDocumentUseCase
    private let submitOnboarding: SubmitDriverOnboardingUseCase
    private let eligibility = DriverEligibilityPolicy()
    private var profile: DriverProfileDetail?

    public init(
        loadProfile: LoadDriverProfileUseCase,
        uploadDocument: UploadDriverDocumentUseCase,
        submitOnboarding: SubmitDriverOnboardingUseCase
    ) {
        self.loadProfile = loadProfile
        self.uploadDocument = uploadDocument
        self.submitOnboarding = submitOnboarding
    }

    public func load() async {
        state = .loading
        do {
            let profile = try await loadProfile()
            apply(profile: profile)
        } catch {
            state = .failed(Self.message(for: error))
        }
    }

    public func submit() async {
        guard isSubmitting == false else { return }
        guard let profile else { return }
        guard eligibility.canSubmitOnboarding(profile) else {
            message = "Upload the required documents before submitting."
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let updated = try await submitOnboarding()
            message = "Documents submitted for review."
            apply(profile: updated)
        } catch {
            message = Self.message(for: error)
        }
    }

    public func upload(_ upload: DriverDocumentUpload) async {
        guard isUploading == false else { return }
        isUploading = true
        defer { isUploading = false }

        do {
            _ = try await uploadDocument(upload)
            let updated = try await loadProfile()
            message = "Document uploaded."
            apply(profile: updated)
        } catch {
            message = Self.message(for: error)
        }
    }

    public func dismissMessage() {
        message = nil
    }

    private func apply(profile: DriverProfileDetail) {
        self.profile = profile
        state = .loaded(DriverProfileSummary(profile: profile, canOperate: eligibility.canOperate(profile), canSubmit: eligibility.canSubmitOnboarding(profile)))
    }

    private static func message(for error: Error) -> String {
        if let failure = error as? DriverProfileFailure {
            switch failure {
            case .validation(let message), .notFound(let message), .unavailable(let message), .conflict(let message), .transient(let message), .server(let message):
                return message
            case .unauthorized:
                return "Sign in again to continue."
            case .forbidden:
                return "This account cannot access driver profile details."
            }
        }
        return error.localizedDescription
    }
}

public struct DriverProfileSummary: Equatable {
    public let id: UUID
    public let fullName: String
    public let phone: String
    public let maskedPhone: String
    public let statusTitle: String
    public let statusDetail: String
    public let statusIconName: String
    public let primaryAction: DriverProfilePrimaryAction
    public let canOperate: Bool
    public let canSubmit: Bool
    public let vehicle: DriverVehicle?
    public let vehicleTitle: String
    public let vehicleDetail: String
    public let checklist: [DriverChecklistItem]
    public let documents: [DriverDocumentRow]
    public let supportOptions: [DriverSupportOption]

    public init(profile: DriverProfileDetail, canOperate: Bool, canSubmit: Bool) {
        self.id = profile.id
        self.fullName = profile.fullName
        self.phone = profile.phone
        self.maskedPhone = Self.maskedPhone(profile.phone)
        self.statusTitle = Self.title(for: profile.status, canOperate: canOperate)
        self.statusDetail = Self.detail(for: profile, canOperate: canOperate)
        self.statusIconName = Self.iconName(for: profile.status, canOperate: canOperate)
        self.primaryAction = Self.primaryAction(for: profile, canOperate: canOperate, canSubmit: canSubmit)
        self.canOperate = canOperate
        self.canSubmit = canSubmit
        self.vehicle = profile.vehicle
        self.vehicleTitle = Self.vehicleTitle(profile.vehicle)
        self.vehicleDetail = Self.vehicleDetail(profile.vehicle)
        self.checklist = Self.makeChecklist(profile: profile)
        self.documents = Self.makeDocuments(profile: profile)
        self.supportOptions = []
    }

    private static func makeChecklist(profile: DriverProfileDetail) -> [DriverChecklistItem] {
        let types = DriverDocumentType.requiredForOnboarding + (profile.vehicle == nil ? [] : DriverDocumentType.requiredForVehicle)
        return types.map { type in
            let document = profile.documents.first { $0.type == type }
            return DriverChecklistItem(
                type: type,
                title: type.displayTitle,
                state: state(for: type, document: document, readiness: profile.readiness),
                detail: detail(for: type, document: document, readiness: profile.readiness)
            )
        }
    }

    private static func makeDocuments(profile: DriverProfileDetail) -> [DriverDocumentRow] {
        makeChecklist(profile: profile).map { item in
            let document = profile.documents.first { $0.type == item.type }
            return DriverDocumentRow(
                type: item.type,
                title: item.title,
                subtitle: item.detail,
                status: item.state,
                rejectionReason: document?.rejectionReason,
                expiresOn: document?.expiresOn,
                canUpload: profile.status.allowsDocumentUpload && item.state != .approved,
                actionTitle: item.state == .missing ? "Upload" : "Replace"
            )
        }
    }

    private static func state(
        for type: DriverDocumentType,
        document: DriverDocument?,
        readiness: DriverReadiness
    ) -> DriverChecklistState {
        if readiness.missing.contains(type) { return .missing }
        if readiness.pendingReview.contains(type) { return .pending }
        if readiness.expired.contains(type) { return .expired }
        switch document?.status {
        case .approved:
            return .approved
        case .rejected:
            return .rejected
        case .pendingReview:
            return .pending
        default:
            return .missing
        }
    }

    private static func title(for status: DriverOperationalStatus, canOperate: Bool) -> String {
        switch status {
        case .pending:
            return "Complete your application"
        case .documentsSubmitted:
            return "Your application is under review"
        case .training:
            return "Training is required"
        case .approved:
            return canOperate ? "You're ready to drive" : "Approved, requirements pending"
        case .rejected:
            return "Application not approved"
        case .suspended:
            return "Account restricted"
        case .unknown:
            return "Profile needs review"
        }
    }

    private static func detail(for profile: DriverProfileDetail, canOperate: Bool) -> String {
        if canOperate {
            return "Your account is ready for driver work. Online availability is separate and depends on server-supported availability APIs."
        }
        switch profile.status {
        case .pending:
            return "Upload the required documents, then submit your application."
        case .documentsSubmitted:
            return "Your documents were submitted. You can check back here for updates."
        case .training:
            return "Training must be completed before you can drive."
        case .approved:
            return outstandingRequirement(for: profile).detail
        case .rejected:
            return latestReason(for: profile, status: .rejected) ?? "Your application was not approved. No self-service appeal action is available in the driver API."
        case .suspended:
            return latestReason(for: profile, status: .suspended) ?? "Driver access is restricted. No self-service reinstatement action is available in the driver API."
        case .unknown:
            return "We could not read this driver status. Try again or sign out and contact your operator."
        }
    }

    private static func primaryAction(for profile: DriverProfileDetail, canOperate: Bool, canSubmit: Bool) -> DriverProfilePrimaryAction {
        if canOperate {
            return DriverProfilePrimaryAction(title: "No action needed", detail: "You're ready to drive.", kind: .none)
        }
        if canSubmit {
            return DriverProfilePrimaryAction(title: "Submit application", detail: "All required onboarding documents are uploaded.", kind: .submitApplication)
        }
        switch profile.status {
        case .pending, .approved:
            let requirement = outstandingRequirement(for: profile)
            return DriverProfilePrimaryAction(title: requirement.actionTitle, detail: requirement.detail, kind: requirement.kind)
        case .documentsSubmitted:
            return DriverProfilePrimaryAction(title: "Wait for review", detail: "Your application is with the operations team.", kind: .none)
        case .training:
            return DriverProfilePrimaryAction(title: "Complete training", detail: "Follow the training instructions from your operator.", kind: .none)
        case .rejected, .suspended, .unknown:
            return DriverProfilePrimaryAction(title: "Contact operator", detail: "No in-app action is currently supported for this account status.", kind: .none)
        }
    }

    private static func outstandingRequirement(for profile: DriverProfileDetail) -> DriverOutstandingRequirement {
        if profile.readiness.hasActiveVehicle == false {
            return DriverOutstandingRequirement(
                detail: "An active vehicle assignment is required before you can drive.",
                actionTitle: "Contact operator",
                kind: .none
            )
        }
        if let type = profile.readiness.expired.first {
            return DriverOutstandingRequirement(
                detail: "\(type.displayTitle) has expired. Upload a replacement document.",
                actionTitle: "Replace \(type.displayTitle)",
                kind: .openDocument(type)
            )
        }
        if let type = profile.documents.first(where: { $0.status == .rejected })?.type {
            return DriverOutstandingRequirement(
                detail: "\(type.displayTitle) needs replacement.",
                actionTitle: "Replace \(type.displayTitle)",
                kind: .openDocument(type)
            )
        }
        if let type = profile.readiness.missing.first {
            return DriverOutstandingRequirement(
                detail: "\(type.displayTitle) is required.",
                actionTitle: "Upload \(type.displayTitle)",
                kind: .openDocument(type)
            )
        }
        if let type = profile.readiness.pendingReview.first {
            return DriverOutstandingRequirement(
                detail: "\(type.displayTitle) is under review.",
                actionTitle: "Wait for review",
                kind: .none
            )
        }
        return DriverOutstandingRequirement(
            detail: "Your profile is not ready yet.",
            actionTitle: "Review requirements",
            kind: .none
        )
    }

    private static func detail(for type: DriverDocumentType, document: DriverDocument?, readiness: DriverReadiness) -> String {
        if let reason = document?.rejectionReason, document?.status == .rejected {
            return reason
        }
        if readiness.expired.contains(type) {
            return document?.expiresOn.map { "Expired \($0)" } ?? "Expired"
        }
        if readiness.pendingReview.contains(type) || document?.status == .pendingReview {
            return "We'll update this after review."
        }
        if let expiresOn = document?.expiresOn {
            return "Expires \(expiresOn)"
        }
        if readiness.missing.contains(type) || document == nil {
            return "Not uploaded yet."
        }
        return "Uploaded."
    }

    private static func latestReason(for profile: DriverProfileDetail, status: DriverOperationalStatus) -> String? {
        profile.history.last { $0.to == status }?.reason
    }

    private static func iconName(for status: DriverOperationalStatus, canOperate: Bool) -> String {
        if canOperate { return "checkmark.seal.fill" }
        switch status {
        case .pending:
            return "doc.badge.plus"
        case .documentsSubmitted:
            return "clock.badge.checkmark"
        case .training:
            return "graduationcap.fill"
        case .approved:
            return "exclamationmark.triangle.fill"
        case .rejected:
            return "xmark.octagon.fill"
        case .suspended:
            return "lock.fill"
        case .unknown:
            return "questionmark.circle.fill"
        }
    }

    private static func maskedPhone(_ phone: String) -> String {
        let digits = phone.filter(\.isNumber)
        guard digits.count > 4 else { return phone }
        return "+\(String(digits.prefix(3))) ••• ••• \(String(digits.suffix(3)))"
    }

    private static func vehicleTitle(_ vehicle: DriverVehicle?) -> String {
        guard let vehicle else { return "No active vehicle assigned" }
        return "\(vehicle.make) \(vehicle.model)"
    }

    private static func vehicleDetail(_ vehicle: DriverVehicle?) -> String {
        guard let vehicle else {
            return "Vehicle assignment is managed by your operator. No in-app assignment change is available."
        }
        return "\(vehicle.plateNumber) · \(vehicle.color) · \(vehicle.seats) seats"
    }
}

private struct DriverOutstandingRequirement {
    let detail: String
    let actionTitle: String
    let kind: DriverProfilePrimaryAction.Kind
}

public struct DriverProfilePrimaryAction: Equatable {
    public enum Kind: Equatable {
        case none
        case submitApplication
        case openDocument(DriverDocumentType)
    }

    public let title: String
    public let detail: String
    public let kind: Kind
}

public struct DriverChecklistItem: Equatable {
    public let type: DriverDocumentType
    public let title: String
    public let state: DriverChecklistState
    public let detail: String
}

public struct DriverDocumentRow: Equatable {
    public let type: DriverDocumentType
    public let title: String
    public let subtitle: String
    public let status: DriverChecklistState
    public let rejectionReason: String?
    public let expiresOn: String?
    public let canUpload: Bool
    public let actionTitle: String
}

public struct DriverSupportOption: Equatable {
    public let title: String
    public let detail: String
}

public enum DriverChecklistState: Equatable {
    case missing
    case pending
    case approved
    case rejected
    case expired

    public var title: String {
        switch self {
        case .missing:
            return "Not uploaded"
        case .pending:
            return "Under review"
        case .approved:
            return "Approved"
        case .rejected:
            return "Needs replacement"
        case .expired:
            return "Expired"
        }
    }
}

public extension DriverDocumentType {
    var displayTitle: String {
        switch self {
        case .nationalID:
            return "National ID"
        case .drivingLicense:
            return "Driving licence"
        case .profilePhoto:
            return "Profile photo"
        case .vehicleRegistration:
            return "Vehicle registration"
        case .vehicleInsurance:
            return "Vehicle insurance"
        }
    }
}
