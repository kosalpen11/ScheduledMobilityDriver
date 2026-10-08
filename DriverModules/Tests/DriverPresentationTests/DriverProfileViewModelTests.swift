//
//  DriverProfileViewModelTests.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/4/26.
//

import DriverDomain
import DriverPresentation
import XCTest

@MainActor
final class DriverProfileViewModelTests: XCTestCase {
    func testDuplicateSubmitIsIgnoredWhileInFlight() async {
        let repository = SlowProfileRepository(profile: Self.submittableProfile())
        let model = DriverProfileViewModel(
            loadProfile: LoadDriverProfileUseCase(repository: repository),
            loadDocuments: LoadDriverDocumentsUseCase(repository: repository),
            uploadDocument: UploadDriverDocumentUseCase(repository: repository),
            submitOnboarding: SubmitDriverOnboardingUseCase(repository: repository)
        )

        await model.load()
        async let first: Void = model.submit()
        async let second: Void = model.submit()
        _ = await (first, second)

        let submitCount = await repository.currentSubmitCount()
        XCTAssertEqual(submitCount, 1)
    }

    func testUploadValidationFailureDoesNotCallRepositoryUpload() async {
        let repository = SlowProfileRepository(profile: Self.submittableProfile())
        let model = DriverProfileViewModel(
            loadProfile: LoadDriverProfileUseCase(repository: repository),
            loadDocuments: LoadDriverDocumentsUseCase(repository: repository),
            uploadDocument: UploadDriverDocumentUseCase(repository: repository),
            submitOnboarding: SubmitDriverOnboardingUseCase(repository: repository)
        )

        await model.upload(DriverDocumentUpload(type: .profilePhoto, vehicleID: nil, expiresOn: nil, filename: "bad.txt", content: Data("bad".utf8)))

        let uploadCount = await repository.currentUploadCount()
        XCTAssertEqual(uploadCount, 0)
        XCTAssertEqual(model.message, "Upload a JPEG, PNG, or PDF file.")
    }

    func testSubmitUploadsStagedDocumentsConcurrentlyBeforeSubmit() async {
        let repository = BatchProfileRepository(profile: Self.missingDocumentsProfile())
        let model = DriverProfileViewModel(
            loadProfile: LoadDriverProfileUseCase(repository: repository),
            loadDocuments: LoadDriverDocumentsUseCase(repository: repository),
            uploadDocument: UploadDriverDocumentUseCase(repository: repository),
            submitOnboarding: SubmitDriverOnboardingUseCase(repository: repository)
        )
        let jpeg = Data([0xFF, 0xD8, 0xFF])
        let expiry = Date(timeIntervalSinceNow: 86_400 * 365)

        await model.load()
        model.stage(DriverDocumentUpload(
            type: .nationalID,
            vehicleID: nil,
            expiresOn: expiry,
            files: [
                DriverDocumentUploadFile(fieldName: "front", filename: "front.jpg", content: jpeg),
                DriverDocumentUploadFile(fieldName: "back", filename: "back.jpg", content: jpeg)
            ]
        ))
        model.stage(DriverDocumentUpload(type: .drivingLicense, vehicleID: nil, expiresOn: expiry, filename: "license.jpg", content: jpeg))
        model.stage(DriverDocumentUpload(type: .profilePhoto, vehicleID: nil, expiresOn: nil, filename: "profile.jpg", content: jpeg))

        await model.submit()

        let uploadCount = await repository.currentUploadCount()
        let submitCount = await repository.currentSubmitCount()
        let maxActiveUploads = await repository.currentMaxActiveUploads()
        XCTAssertEqual(uploadCount, 3)
        XCTAssertEqual(submitCount, 1)
        XCTAssertGreaterThan(maxActiveUploads, 1)
    }

    private static func submittableProfile() -> DriverProfileDetail {
        DriverProfileDetail(
            id: UUID(),
            userID: UUID(),
            fullName: "Driver",
            phone: "+85512000002",
            status: .pending,
            nationalIDMasked: nil,
            vehicle: nil,
            documents: DriverDocumentType.requiredForOnboarding.map {
                DriverDocument(
                    id: UUID(),
                    type: $0,
                    vehicleID: nil,
                    status: .approved,
                    contentType: $0 == .profilePhoto ? "image/jpeg" : "application/pdf",
                    sizeBytes: 64,
                    files: files(for: $0),
                    expiresOn: $0.requiresExpiry ? "2030-01-01" : nil,
                    uploadedAt: nil,
                    reviewedAt: nil,
                    rejectionReason: nil,
                    expiryFlaggedAt: nil
                )
            },
            readiness: DriverReadiness(missing: [], pendingReview: [], expired: [], hasActiveVehicle: false),
            createdAt: nil
        )
    }

    private static func missingDocumentsProfile() -> DriverProfileDetail {
        DriverProfileDetail(
            id: UUID(),
            userID: UUID(),
            fullName: "Driver",
            phone: "+85512000002",
            status: .pending,
            nationalIDMasked: nil,
            vehicle: nil,
            documents: [],
            readiness: DriverReadiness(missing: DriverDocumentType.requiredForOnboarding, pendingReview: [], expired: [], hasActiveVehicle: false),
            createdAt: nil
        )
    }

    private static func files(for type: DriverDocumentType) -> [DriverDocumentFile] {
        if type == .nationalID {
            return [
                DriverDocumentFile(contentType: "image/jpeg", side: "front", sizeBytes: 32),
                DriverDocumentFile(contentType: "image/jpeg", side: "back", sizeBytes: 32)
            ]
        }
        return [
            DriverDocumentFile(contentType: type == .profilePhoto ? "image/jpeg" : "application/pdf", side: nil, sizeBytes: 64)
        ]
    }
}

private actor BatchProfileRepository: DriverProfileRepository {
    private var profile: DriverProfileDetail
    private(set) var submitCount = 0
    private(set) var uploadCount = 0
    private var activeUploads = 0
    private var maxActiveUploads = 0

    init(profile: DriverProfileDetail) {
        self.profile = profile
    }

    func loadProfile() async throws -> DriverProfileDetail {
        profile
    }

    func loadDocuments() async throws -> [DriverDocument] {
        profile.documents
    }

    func uploadDocument(_ upload: DriverDocumentUpload) async throws -> DriverDocument {
        uploadCount += 1
        activeUploads += 1
        maxActiveUploads = max(maxActiveUploads, activeUploads)
        try await Task.sleep(nanoseconds: 40_000_000)
        activeUploads -= 1

        let files = try DriverDocumentUploadValidator().validateFiles(upload)
        let document = DriverDocument(
            id: UUID(),
            type: upload.type,
            vehicleID: upload.vehicleID,
            status: .pendingReview,
            contentType: files.first?.kind.contentType ?? "image/jpeg",
            sizeBytes: upload.files.reduce(0) { $0 + $1.content.count },
            files: files.map {
                DriverDocumentFile(
                    contentType: $0.kind.contentType,
                    side: $0.file.fieldName == "file" ? nil : $0.file.fieldName,
                    sizeBytes: $0.file.content.count
                )
            },
            expiresOn: upload.expiresOn.map { _ in "2030-01-01" },
            uploadedAt: nil,
            reviewedAt: nil,
            rejectionReason: nil,
            expiryFlaggedAt: nil
        )
        profile = profile.replacingUploaded(document)
        return document
    }

    func submitOnboarding() async throws -> DriverProfileDetail {
        submitCount += 1
        guard profile.hasRequiredOnboardingDocumentsForSubmit else {
            throw DriverProfileFailure.conflict("Upload the required documents first.")
        }
        profile = DriverProfileDetail(
            id: profile.id,
            userID: profile.userID,
            fullName: profile.fullName,
            phone: profile.phone,
            status: .documentsSubmitted,
            nationalIDMasked: profile.nationalIDMasked,
            vehicle: profile.vehicle,
            documents: profile.documents,
            readiness: profile.readiness,
            createdAt: profile.createdAt
        )
        return profile
    }

    func clearSessionState() async {}

    func currentUploadCount() -> Int {
        uploadCount
    }

    func currentSubmitCount() -> Int {
        submitCount
    }

    func currentMaxActiveUploads() -> Int {
        maxActiveUploads
    }
}

private extension DriverProfileDetail {
    func replacingUploaded(_ document: DriverDocument) -> DriverProfileDetail {
        let documents = self.documents.filter { $0.type != document.type || $0.vehicleID != document.vehicleID } + [document]
        let missing = DriverDocumentType.requiredForOnboarding.filter { type in
            guard let document = documents.first(where: { $0.type == type }) else { return true }
            if type == .nationalID {
                return document.hasFile(side: "front") == false || document.hasFile(side: "back") == false
            }
            return false
        }
        return DriverProfileDetail(
            id: id,
            userID: userID,
            fullName: fullName,
            phone: phone,
            status: status,
            nationalIDMasked: nationalIDMasked,
            vehicle: vehicle,
            documents: documents,
            readiness: DriverReadiness(missing: missing, pendingReview: documents.map(\.type), expired: [], hasActiveVehicle: readiness.hasActiveVehicle),
            createdAt: createdAt
        )
    }
}

private actor SlowProfileRepository: DriverProfileRepository {
    private var profile: DriverProfileDetail
    private(set) var submitCount = 0
    private(set) var uploadCount = 0

    init(profile: DriverProfileDetail) {
        self.profile = profile
    }

    func loadProfile() async throws -> DriverProfileDetail {
        profile
    }

    func loadDocuments() async throws -> [DriverDocument] {
        profile.documents
    }

    func uploadDocument(_ upload: DriverDocumentUpload) async throws -> DriverDocument {
        uploadCount += 1
        throw DriverProfileFailure.server("Unexpected upload.")
    }

    func submitOnboarding() async throws -> DriverProfileDetail {
        submitCount += 1
        try await Task.sleep(nanoseconds: 60_000_000)
        profile = DriverProfileDetail(
            id: profile.id,
            userID: profile.userID,
            fullName: profile.fullName,
            phone: profile.phone,
            status: .documentsSubmitted,
            nationalIDMasked: profile.nationalIDMasked,
            vehicle: profile.vehicle,
            documents: profile.documents,
            readiness: profile.readiness,
            createdAt: profile.createdAt
        )
        return profile
    }

    func clearSessionState() async {}

    func currentSubmitCount() -> Int {
        submitCount
    }

    func currentUploadCount() -> Int {
        uploadCount
    }
}
