//
//  DriverProfileModels.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/4/26.
//

import Foundation

public enum DriverOperationalStatus: String, Equatable, Sendable, CaseIterable {
    case pending = "PENDING"
    case documentsSubmitted = "DOCS_SUBMITTED"
    case training = "TRAINING"
    case approved = "APPROVED"
    case rejected = "REJECTED"
    case suspended = "SUSPENDED"
    case unknown

    public var allowsDocumentUpload: Bool {
        self != .rejected
    }
}

public enum DriverDocumentType: String, Equatable, Sendable, CaseIterable {
    case nationalID = "NATIONAL_ID"
    case drivingLicense = "DRIVING_LICENSE"
    case profilePhoto = "PROFILE_PHOTO"
    case vehicleRegistration = "VEHICLE_REGISTRATION"
    case vehicleInsurance = "VEHICLE_INSURANCE"

    public static let requiredForOnboarding: [DriverDocumentType] = [
        .nationalID,
        .drivingLicense,
        .profilePhoto
    ]

    public static let requiredForVehicle: [DriverDocumentType] = [
        .vehicleRegistration,
        .vehicleInsurance
    ]

    public var requiresExpiry: Bool {
        self != .profilePhoto
    }

    public var isVehicleDocument: Bool {
        self == .vehicleRegistration || self == .vehicleInsurance
    }

    public var defaultUploadFieldName: String {
        self == .nationalID ? "front" : "file"
    }
}

public enum DriverDocumentStatus: String, Equatable, Sendable {
    case pendingReview = "PENDING_REVIEW"
    case approved = "APPROVED"
    case rejected = "REJECTED"
    case superseded = "SUPERSEDED"
    case unknown
}

public struct DriverDocument: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let type: DriverDocumentType
    public let vehicleID: UUID?
    public let status: DriverDocumentStatus
    public let contentType: String
    public let sizeBytes: Int
    public let expiresOn: String?
    public let uploadedAt: String?
    public let reviewedAt: String?
    public let rejectionReason: String?
    public let expiryFlaggedAt: String?

    public init(
        id: UUID,
        type: DriverDocumentType,
        vehicleID: UUID?,
        status: DriverDocumentStatus,
        contentType: String,
        sizeBytes: Int,
        expiresOn: String?,
        uploadedAt: String?,
        reviewedAt: String?,
        rejectionReason: String?,
        expiryFlaggedAt: String?
    ) {
        self.id = id
        self.type = type
        self.vehicleID = vehicleID
        self.status = status
        self.contentType = contentType
        self.sizeBytes = sizeBytes
        self.expiresOn = expiresOn
        self.uploadedAt = uploadedAt
        self.reviewedAt = reviewedAt
        self.rejectionReason = rejectionReason
        self.expiryFlaggedAt = expiryFlaggedAt
    }
}

public enum DriverVehicleClass: String, Equatable, Sendable {
    case moto = "MOTO"
    case tuktukRemork = "TUKTUK_REMORK"
    case tuktukRickshaw = "TUKTUK_RICKSHAW"
    case car = "CAR"
    case suv = "SUV"
    case van = "VAN"
    case unknown
}

public enum DriverVehicleStatus: String, Equatable, Sendable {
    case active = "ACTIVE"
    case inactive = "INACTIVE"
    case unknown
}

public struct DriverVehicle: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let plateNumber: String
    public let vehicleClass: DriverVehicleClass
    public let make: String
    public let model: String
    public let color: String
    public let modelYear: Int?
    public let seats: Int
    public let status: DriverVehicleStatus
    public let assignedAt: String?

    public init(
        id: UUID,
        plateNumber: String,
        vehicleClass: DriverVehicleClass,
        make: String,
        model: String,
        color: String,
        modelYear: Int?,
        seats: Int,
        status: DriverVehicleStatus,
        assignedAt: String?
    ) {
        self.id = id
        self.plateNumber = plateNumber
        self.vehicleClass = vehicleClass
        self.make = make
        self.model = model
        self.color = color
        self.modelYear = modelYear
        self.seats = seats
        self.status = status
        self.assignedAt = assignedAt
    }
}

public struct DriverReadiness: Equatable, Sendable {
    public let missing: [DriverDocumentType]
    public let pendingReview: [DriverDocumentType]
    public let expired: [DriverDocumentType]
    public let hasActiveVehicle: Bool

    public init(
        missing: [DriverDocumentType],
        pendingReview: [DriverDocumentType],
        expired: [DriverDocumentType],
        hasActiveVehicle: Bool
    ) {
        self.missing = missing
        self.pendingReview = pendingReview
        self.expired = expired
        self.hasActiveVehicle = hasActiveVehicle
    }

    public var allUploaded: Bool {
        missing.isEmpty
    }

    public var allApprovedAndValid: Bool {
        missing.isEmpty && pendingReview.isEmpty && expired.isEmpty
    }
}

public struct DriverProfileDetail: Equatable, Sendable {
    public let id: UUID
    public let userID: UUID
    public let fullName: String
    public let phone: String
    public let status: DriverOperationalStatus
    public let nationalIDMasked: String?
    public let vehicle: DriverVehicle?
    public let documents: [DriverDocument]
    public let readiness: DriverReadiness
    public let history: [DriverStatusHistoryEntry]
    public let createdAt: String?

    public init(
        id: UUID,
        userID: UUID,
        fullName: String,
        phone: String,
        status: DriverOperationalStatus,
        nationalIDMasked: String?,
        vehicle: DriverVehicle?,
        documents: [DriverDocument],
        readiness: DriverReadiness,
        history: [DriverStatusHistoryEntry] = [],
        createdAt: String?
    ) {
        self.id = id
        self.userID = userID
        self.fullName = fullName
        self.phone = phone
        self.status = status
        self.nationalIDMasked = nationalIDMasked
        self.vehicle = vehicle
        self.documents = documents
        self.readiness = readiness
        self.history = history
        self.createdAt = createdAt
    }
}

public struct DriverStatusHistoryEntry: Equatable, Sendable {
    public let from: DriverOperationalStatus?
    public let to: DriverOperationalStatus
    public let reason: String?
    public let noticeAt: String?
    public let occurredAt: String?

    public init(
        from: DriverOperationalStatus?,
        to: DriverOperationalStatus,
        reason: String?,
        noticeAt: String?,
        occurredAt: String?
    ) {
        self.from = from
        self.to = to
        self.reason = reason
        self.noticeAt = noticeAt
        self.occurredAt = occurredAt
    }
}

public struct DriverDocumentUpload: Equatable, Sendable {
    public let type: DriverDocumentType
    public let vehicleID: UUID?
    public let expiresOn: Date?
    public let files: [DriverDocumentUploadFile]

    public var filename: String {
        files.first?.filename ?? ""
    }

    public var content: Data {
        files.first?.content ?? Data()
    }

    public init(
        type: DriverDocumentType,
        vehicleID: UUID?,
        expiresOn: Date?,
        filename: String,
        content: Data
    ) {
        self.init(
            type: type,
            vehicleID: vehicleID,
            expiresOn: expiresOn,
            files: [
                DriverDocumentUploadFile(
                    fieldName: type.defaultUploadFieldName,
                    filename: filename,
                    content: content
                )
            ]
        )
    }

    public init(
        type: DriverDocumentType,
        vehicleID: UUID?,
        expiresOn: Date?,
        files: [DriverDocumentUploadFile]
    ) {
        self.type = type
        self.vehicleID = vehicleID
        self.expiresOn = expiresOn
        self.files = files
    }
}

public struct DriverDocumentUploadFile: Equatable, Sendable {
    public let fieldName: String
    public let filename: String
    public let content: Data

    public init(fieldName: String, filename: String, content: Data) {
        self.fieldName = fieldName
        self.filename = filename
        self.content = content
    }
}

public struct DriverEligibilityPolicy: Sendable {
    public init() {}

    public func canOperate(_ profile: DriverProfileDetail) -> Bool {
        profile.status == .approved && profile.readiness.hasActiveVehicle && profile.readiness.allApprovedAndValid
    }

    public func canSubmitOnboarding(_ profile: DriverProfileDetail) -> Bool {
        profile.status == .pending && profile.readiness.allUploaded
    }
}

public enum DriverProfileFailure: Error, Equatable, Sendable {
    case validation(String)
    case notFound(String)
    case unauthorized
    case forbidden
    case unavailable(String)
    case conflict(String)
    case transient(String)
    case server(String)
}

public enum DriverUploadFileKind: Equatable, Sendable {
    case jpeg
    case png
    case pdf

    public var contentType: String {
        switch self {
        case .jpeg:
            return "image/jpeg"
        case .png:
            return "image/png"
        case .pdf:
            return "application/pdf"
        }
    }
}

public struct DriverDocumentUploadValidator: Sendable {
    public let today: @Sendable () -> Date

    public init(today: @escaping @Sendable () -> Date = { Date() }) {
        self.today = today
    }

    public func validate(_ upload: DriverDocumentUpload) throws -> DriverUploadFileKind {
        guard let first = try validateFiles(upload).first else {
            throw DriverProfileFailure.validation("Choose a file before uploading.")
        }
        return first.kind
    }

    public func validateFiles(_ upload: DriverDocumentUpload) throws -> [DriverValidatedUploadFile] {
        guard upload.files.isEmpty == false else {
            throw DriverProfileFailure.validation("Choose a file before uploading.")
        }

        let files = try upload.files.map { file in
            guard file.fieldName.isEmpty == false, file.content.isEmpty == false else {
                throw DriverProfileFailure.validation("Choose a file before uploading.")
            }
            guard file.content.count <= 10 * 1024 * 1024 else {
                throw DriverProfileFailure.validation("Documents must be 10 MB or smaller.")
            }
            guard let kind = Self.detectFileKind(file.content) else {
                throw DriverProfileFailure.validation("Upload a JPEG, PNG, or PDF file.")
            }
            if upload.type == .profilePhoto && kind == .pdf {
                throw DriverProfileFailure.validation("Profile photo must be a JPEG or PNG image.")
            }
            return DriverValidatedUploadFile(file: file, kind: kind)
        }

        if upload.type == .nationalID {
            let fieldNames = Set(files.map(\.file.fieldName))
            guard fieldNames.isSubset(of: ["front", "back"]) else {
                throw DriverProfileFailure.validation("National ID files must be submitted as front or back images.")
            }
            guard fieldNames.contains("front") else {
                throw DriverProfileFailure.validation("Upload the front side of the National ID.")
            }
        }
        if upload.type.requiresExpiry {
            guard let expiresOn = upload.expiresOn else {
                throw DriverProfileFailure.validation("Enter the document expiry date.")
            }
            if Calendar.current.startOfDay(for: expiresOn) < Calendar.current.startOfDay(for: today()) {
                throw DriverProfileFailure.validation("Expiry date cannot be in the past.")
            }
        }
        if upload.type.isVehicleDocument {
            guard upload.vehicleID != nil else {
                throw DriverProfileFailure.validation("Vehicle documents require an assigned active vehicle.")
            }
        } else if upload.vehicleID != nil {
            throw DriverProfileFailure.validation("This document is not linked to a vehicle.")
        }
        return files
    }

    public static func detectFileKind(_ data: Data) -> DriverUploadFileKind? {
        let bytes = [UInt8](data.prefix(8))
        if bytes.count >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF {
            return .jpeg
        }
        if bytes.count >= 8 &&
            bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47 &&
            bytes[4] == 0x0D && bytes[5] == 0x0A && bytes[6] == 0x1A && bytes[7] == 0x0A {
            return .png
        }
        if bytes.count >= 5 && bytes[0] == 0x25 && bytes[1] == 0x50 && bytes[2] == 0x44 && bytes[3] == 0x46 && bytes[4] == 0x2D {
            return .pdf
        }
        return nil
    }
}

public struct DriverValidatedUploadFile: Equatable, Sendable {
    public let file: DriverDocumentUploadFile
    public let kind: DriverUploadFileKind

    public init(file: DriverDocumentUploadFile, kind: DriverUploadFileKind) {
        self.file = file
        self.kind = kind
    }
}
