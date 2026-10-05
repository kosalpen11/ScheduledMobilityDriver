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
            uploadDocument: UploadDriverDocumentUseCase(repository: repository),
            submitOnboarding: SubmitDriverOnboardingUseCase(repository: repository)
        )

        await model.upload(DriverDocumentUpload(type: .profilePhoto, vehicleID: nil, expiresOn: nil, filename: "bad.txt", content: Data("bad".utf8)))

        let uploadCount = await repository.currentUploadCount()
        XCTAssertEqual(uploadCount, 0)
        XCTAssertEqual(model.message, "Upload a JPEG, PNG, or PDF file.")
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
