//
//  DriverProfileTests.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/4/26.
//

import DriverDomain
import XCTest

final class DriverProfileTests: XCTestCase {
    func testEligibilityRequiresApprovalVehicleAndCleanReadiness() {
        let policy = DriverEligibilityPolicy()
        var profile = makeProfile(status: .approved, readiness: DriverReadiness(missing: [], pendingReview: [], expired: [], hasActiveVehicle: true))
        XCTAssertTrue(policy.canOperate(profile))

        profile = makeProfile(status: .approved, readiness: DriverReadiness(missing: [], pendingReview: [.drivingLicense], expired: [], hasActiveVehicle: true))
        XCTAssertFalse(policy.canOperate(profile))

        profile = makeProfile(status: .training, readiness: DriverReadiness(missing: [], pendingReview: [], expired: [], hasActiveVehicle: true))
        XCTAssertFalse(policy.canOperate(profile))

        profile = makeProfile(status: .approved, readiness: DriverReadiness(missing: [], pendingReview: [], expired: [], hasActiveVehicle: false))
        XCTAssertFalse(policy.canOperate(profile))
    }

    func testUploadValidationDetectsContentAndRejectsProfilePDF() throws {
        let validator = DriverDocumentUploadValidator(today: { Date(timeIntervalSince1970: 0) })
        let pdf = Data("%PDF-1.7".utf8)
        let upload = DriverDocumentUpload(type: .profilePhoto, vehicleID: nil, expiresOn: nil, filename: "photo.pdf", content: pdf)

        XCTAssertThrowsError(try validator.validate(upload)) { error in
            XCTAssertEqual(error as? DriverProfileFailure, .validation("Profile photo must be a JPEG or PNG image."))
        }
    }

    func testUploadValidationRequiresVehicleForVehicleDocuments() throws {
        let validator = DriverDocumentUploadValidator(today: { Date(timeIntervalSince1970: 0) })
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let upload = DriverDocumentUpload(
            type: .vehicleInsurance,
            vehicleID: nil,
            expiresOn: Date(timeIntervalSince1970: 86_400),
            filename: "insurance.png",
            content: png
        )

        XCTAssertThrowsError(try validator.validate(upload)) { error in
            XCTAssertEqual(error as? DriverProfileFailure, .validation("Vehicle documents require an assigned active vehicle."))
        }
    }

    func testNationalIDUploadRequiresFrontAndBackFields() throws {
        let jpeg = Data([0xFF, 0xD8, 0xFF])
        let upload = DriverDocumentUpload(
            type: .nationalID,
            vehicleID: nil,
            expiresOn: Date(timeIntervalSince1970: 86_400),
            filename: "national-id.jpg",
            content: jpeg
        )

        XCTAssertEqual(upload.files.map(\.fieldName), ["front"])
        XCTAssertThrowsError(try DriverDocumentUploadValidator(today: { Date(timeIntervalSince1970: 0) }).validate(upload)) { error in
            XCTAssertEqual(error as? DriverProfileFailure, .validation("Upload the back side of the National ID."))
        }
    }

    func testNationalIDUploadAcceptsFrontAndBackFields() throws {
        let jpeg = Data([0xFF, 0xD8, 0xFF])
        let upload = DriverDocumentUpload(
            type: .nationalID,
            vehicleID: nil,
            expiresOn: Date(timeIntervalSince1970: 86_400),
            files: [
                DriverDocumentUploadFile(fieldName: "front", filename: "front.jpg", content: jpeg),
                DriverDocumentUploadFile(fieldName: "back", filename: "back.jpg", content: jpeg)
            ]
        )

        let files = try DriverDocumentUploadValidator(today: { Date(timeIntervalSince1970: 0) }).validateFiles(upload)
        XCTAssertEqual(files.map(\.file.fieldName), ["front", "back"])
        XCTAssertEqual(files.map(\.kind), [.jpeg, .jpeg])
    }

    func testDocumentSideMatchingIgnoresBackendCase() {
        let document = DriverDocument(
            id: UUID(),
            type: .nationalID,
            vehicleID: nil,
            status: .pendingReview,
            contentType: "image/jpeg",
            sizeBytes: 469_579,
            files: [
                DriverDocumentFile(contentType: "image/jpeg", side: "FRONT", sizeBytes: 469_579),
                DriverDocumentFile(contentType: "image/jpeg", side: "BACK", sizeBytes: 376_100)
            ],
            expiresOn: "2035-06-17",
            uploadedAt: nil,
            reviewedAt: nil,
            rejectionReason: nil,
            expiryFlaggedAt: nil
        )

        XCTAssertTrue(document.hasFile(side: "front"))
        XCTAssertTrue(document.hasFile(side: "back"))
    }

    private func makeProfile(status: DriverOperationalStatus, readiness: DriverReadiness) -> DriverProfileDetail {
        DriverProfileDetail(
            id: UUID(),
            userID: UUID(),
            fullName: "Driver",
            phone: "+85512000002",
            status: status,
            nationalIDMasked: nil,
            vehicle: readiness.hasActiveVehicle ? DriverVehicle(
                id: UUID(),
                plateNumber: "2AB-146",
                vehicleClass: .car,
                make: "Toyota",
                model: "Prius",
                color: "White",
                modelYear: 2017,
                seats: 4,
                status: .active,
                assignedAt: nil
            ) : nil,
            documents: [],
            readiness: readiness,
            createdAt: nil
        )
    }
}
