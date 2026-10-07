//
//  MockDriverProfileRepository.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/4/26.
//

import DriverDomain
import Foundation

public actor MockDriverProfileRepository: DriverProfileRepository {
    public enum Scenario: Sendable {
        case operational
        case pending
        case documentsSubmitted
        case training
        case rejected
        case suspended
        case approvedNotReady
        case missingProfile
    }

    private var profile: DriverProfileDetail
    private let scenario: Scenario
    private var uploadIDs = Set<String>()
    public private(set) var didClearSessionState = false

    public init(profile: DriverProfileDetail? = nil, scenario: Scenario = .operational) {
        self.scenario = scenario
        self.profile = profile ?? Self.defaultProfile(scenario: scenario)
    }

    public func loadProfile() async throws -> DriverProfileDetail {
        if scenario == .missingProfile {
            throw DriverProfileFailure.notFound("Driver profile was not found.")
        }
        return profile
    }

    public func loadDocuments() async throws -> [DriverDocument] {
        profile.documents
    }

    public func uploadDocument(_ upload: DriverDocumentUpload) async throws -> DriverDocument {
        let uploadSize = upload.files.reduce(0) { $0 + $1.content.count }
        let key = "\(upload.type.rawValue)-\(upload.filename)-\(uploadSize)"
        guard uploadIDs.contains(key) == false else {
            throw DriverProfileFailure.conflict("This upload is already in progress.")
        }
        uploadIDs.insert(key)
        defer { uploadIDs.remove(key) }

        let files = try DriverDocumentUploadValidator().validateFiles(upload)
        let document = DriverDocument(
            id: UUID(),
            type: upload.type,
            vehicleID: upload.vehicleID,
            status: .pendingReview,
            contentType: files.first?.kind.contentType ?? "application/octet-stream",
            sizeBytes: uploadSize,
            expiresOn: upload.expiresOn.map(Self.formatDate),
            uploadedAt: ISO8601DateFormatter().string(from: Date()),
            reviewedAt: nil,
            rejectionReason: nil,
            expiryFlaggedAt: nil
        )
        let documents = profile.documents.filter { $0.type != upload.type || $0.vehicleID != upload.vehicleID } + [document]
        profile = profileWith(documents: documents, status: profile.status)
        return document
    }

    public func submitOnboarding() async throws -> DriverProfileDetail {
        guard profile.status == .pending else {
            throw DriverProfileFailure.conflict("Documents can only be submitted while onboarding is pending.")
        }
        guard profile.readiness.allUploaded else {
            throw DriverProfileFailure.conflict("Upload the required documents first.")
        }
        profile = profileWith(documents: profile.documents, status: .documentsSubmitted)
        return profile
    }

    public func clearSessionState() async {
        didClearSessionState = true
    }

    private func profileWith(documents: [DriverDocument], status: DriverOperationalStatus) -> DriverProfileDetail {
        let required = DriverDocumentType.requiredForOnboarding + (profile.vehicle == nil ? [] : DriverDocumentType.requiredForVehicle)
        let missing = required.filter { type in
            documents.contains { $0.type == type && $0.status != .rejected } == false
        }
        let pending = documents.filter { $0.status == .pendingReview }.map(\.type)
        let expired = documents.filter { $0.expiryFlaggedAt != nil }.map(\.type)
        let readiness = DriverReadiness(
            missing: missing,
            pendingReview: pending,
            expired: expired,
            hasActiveVehicle: profile.vehicle?.status == .active
        )
        return DriverProfileDetail(
            id: profile.id,
            userID: profile.userID,
            fullName: profile.fullName,
            phone: profile.phone,
            status: status,
            nationalIDMasked: profile.nationalIDMasked,
            vehicle: profile.vehicle,
            documents: documents,
            readiness: readiness,
            createdAt: profile.createdAt
        )
    }

    private static func defaultProfile(scenario: Scenario) -> DriverProfileDetail {
        let driverID = UUID(uuidString: "2D6BE87F-3B46-41A2-A704-8C42B26E1E23")!
        let vehicleID = UUID(uuidString: "4F49638D-28F5-4CC7-B133-0F6A4BF87A80")!
        let vehicle = DriverVehicle(
            id: vehicleID,
            plateNumber: "ភ្នំពេញ 2AB-146",
            vehicleClass: .car,
            make: "Toyota",
            model: "Prius",
            color: "White",
            modelYear: 2017,
            seats: 4,
            status: .active,
            assignedAt: "2026-10-01T08:00:00Z"
        )
        var documents: [DriverDocument] = [
            mockDocument(.nationalID, status: .approved, expiresOn: "2030-12-31"),
            mockDocument(.drivingLicense, status: scenario == .pending ? .pendingReview : .approved, expiresOn: "2028-03-01"),
            mockDocument(.profilePhoto, status: .approved, expiresOn: nil),
            mockDocument(.vehicleRegistration, status: .approved, expiresOn: "2030-12-31"),
            mockDocument(.vehicleInsurance, status: .approved, expiresOn: "2030-12-31")
        ]
        if scenario == .approvedNotReady || scenario == .pending {
            documents.removeAll { $0.type == .vehicleInsurance }
        }

        let status: DriverOperationalStatus
        switch scenario {
        case .operational, .approvedNotReady, .missingProfile:
            status = .approved
        case .pending:
            status = .pending
        case .documentsSubmitted:
            status = .documentsSubmitted
        case .training:
            status = .training
        case .rejected:
            status = .rejected
        case .suspended:
            status = .suspended
        }

        let required = DriverDocumentType.requiredForOnboarding + DriverDocumentType.requiredForVehicle
        let missing = required.filter { type in
            documents.contains { $0.type == type && $0.status != .rejected } == false
        }
        let pending = documents.filter { $0.status == .pendingReview }.map(\.type)

        return DriverProfileDetail(
            id: driverID,
            userID: UUID(uuidString: "8A11112D-98D3-4F2A-A420-F632F6156E26")!,
            fullName: "Kosal Pen",
            phone: "+85512000002",
            status: status,
            nationalIDMasked: "********1234",
            vehicle: vehicle,
            documents: documents,
            readiness: DriverReadiness(missing: missing, pendingReview: pending, expired: [], hasActiveVehicle: true),
            createdAt: "2026-10-01T08:00:00Z"
        )
    }

    private static func mockDocument(
        _ type: DriverDocumentType,
        status: DriverDocumentStatus,
        expiresOn: String?
    ) -> DriverDocument {
        DriverDocument(
            id: UUID(),
            type: type,
            vehicleID: type.isVehicleDocument ? UUID(uuidString: "4F49638D-28F5-4CC7-B133-0F6A4BF87A80")! : nil,
            status: status,
            contentType: type == .profilePhoto ? "image/jpeg" : "application/pdf",
            sizeBytes: 1_482_240,
            expiresOn: expiresOn,
            uploadedAt: "2026-10-02T09:12:00Z",
            reviewedAt: status == .approved ? "2026-10-03T11:00:00Z" : nil,
            rejectionReason: status == .rejected ? "Image is not readable." : nil,
            expiryFlaggedAt: nil
        )
    }

    private static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
