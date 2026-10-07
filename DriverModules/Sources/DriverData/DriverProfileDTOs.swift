//
//  DriverProfileDTOs.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/4/26.
//

import DriverDomain
import Foundation
import PlatformServices

struct DriverProfileDetailDTO: Decodable {
    let id: UUID
    let userId: UUID
    let fullName: String
    let phone: String
    let status: String
    let nationalIdMasked: String?
    let vehicle: DriverVehicleDTO?
    let documents: [DriverDocumentDTO]?
    let readiness: DriverReadinessDTO?
    let history: [DriverStatusHistoryDTO]?
    let createdAt: String?

    func domain() -> DriverProfileDetail {
        DriverProfileDetail(
            id: id,
            userID: userId,
            fullName: fullName,
            phone: phone,
            status: DriverOperationalStatus(rawValue: status) ?? .unknown,
            nationalIDMasked: nationalIdMasked,
            vehicle: vehicle?.domain(),
            documents: documents?.map { $0.domain() } ?? [],
            readiness: readiness?.domain() ?? DriverReadiness(missing: [], pendingReview: [], expired: [], hasActiveVehicle: vehicle?.status == "ACTIVE"),
            history: history?.map { $0.domain() } ?? [],
            createdAt: createdAt
        )
    }
}

struct DriverStatusHistoryDTO: Decodable {
    let from: String?
    let to: String
    let reason: String?
    let noticeAt: String?
    let occurredAt: String?

    func domain() -> DriverStatusHistoryEntry {
        DriverStatusHistoryEntry(
            from: from.flatMap { DriverOperationalStatus(rawValue: $0) },
            to: DriverOperationalStatus(rawValue: to) ?? .unknown,
            reason: reason,
            noticeAt: noticeAt,
            occurredAt: occurredAt
        )
    }
}

struct DriverReadinessDTO: Decodable {
    let missing: [String]?
    let pendingReview: [String]?
    let expired: [String]?
    let hasActiveVehicle: Bool

    func domain() -> DriverReadiness {
        DriverReadiness(
            missing: mapTypes(missing),
            pendingReview: mapTypes(pendingReview),
            expired: mapTypes(expired),
            hasActiveVehicle: hasActiveVehicle
        )
    }

    private func mapTypes(_ values: [String]?) -> [DriverDocumentType] {
        (values ?? []).compactMap { DriverDocumentType(rawValue: $0) }
    }
}

struct DriverVehicleDTO: Decodable {
    let id: UUID
    let plateNumber: String
    let vehicleClass: String
    let make: String
    let model: String
    let color: String
    let modelYear: Int?
    let seats: Int
    let status: String
    let assignedAt: String?

    func domain() -> DriverVehicle {
        DriverVehicle(
            id: id,
            plateNumber: plateNumber,
            vehicleClass: DriverVehicleClass(rawValue: vehicleClass) ?? .unknown,
            make: make,
            model: model,
            color: color,
            modelYear: modelYear,
            seats: seats,
            status: DriverVehicleStatus(rawValue: status) ?? .unknown,
            assignedAt: assignedAt
        )
    }
}

struct DriverDocumentDTO: Decodable {
    let id: UUID
    let type: String
    let vehicleId: UUID?
    let status: String
    let contentType: String?
    let sizeBytes: Int?
    let files: [DriverDocumentFileDTO]?
    let expiresOn: String?
    let uploadedAt: String?
    let reviewedAt: String?
    let rejectionReason: String?
    let expiryFlaggedAt: String?

    func domain() -> DriverDocument {
        let primaryFile = files?.first
        return DriverDocument(
            id: id,
            type: DriverDocumentType(rawValue: type) ?? .profilePhoto,
            vehicleID: vehicleId,
            status: DriverDocumentStatus(rawValue: status) ?? .unknown,
            contentType: contentType ?? primaryFile?.contentType ?? "application/octet-stream",
            sizeBytes: sizeBytes ?? primaryFile?.sizeBytes ?? 0,
            expiresOn: expiresOn,
            uploadedAt: uploadedAt,
            reviewedAt: reviewedAt,
            rejectionReason: rejectionReason,
            expiryFlaggedAt: expiryFlaggedAt
        )
    }
}

struct DriverDocumentFileDTO: Decodable {
    let contentType: String?
    let side: String?
    let sizeBytes: Int?
}

enum DriverProfileErrorMapper {
    static func map(_ error: Error) -> Error {
        if let auth = error as? AuthFailure {
            switch auth {
            case .unauthorized, .invalidRefreshToken:
                return DriverProfileFailure.unauthorized
            case .forbidden:
                return DriverProfileFailure.forbidden
            case .transient(let message):
                return DriverProfileFailure.transient(message)
            case .validation(let message), .invalidOTP(let message), .inactiveAccount(let message):
                return DriverProfileFailure.validation(message)
            case .rateLimited(_, let message):
                return DriverProfileFailure.server(message)
            case .server(let message):
                return DriverProfileFailure.server(message)
            }
        }

        guard let http = error as? HTTPClientError else {
            return error
        }

        switch http {
        case .badStatus(let status, let problem):
            let message = problem?.detail ?? problem?.title ?? "Request failed."
            switch status {
            case 400:
                return DriverProfileFailure.validation(message)
            case 401:
                return DriverProfileFailure.unauthorized
            case 403:
                return DriverProfileFailure.forbidden
            case 404:
                return DriverProfileFailure.notFound(message)
            case 409:
                return DriverProfileFailure.conflict(message)
            case 413:
                return DriverProfileFailure.validation("Documents must be 10 MB or smaller.")
            case 422:
                return DriverProfileFailure.conflict(message)
            default:
                return DriverProfileFailure.server(message)
            }
        case .transport(let message):
            return DriverProfileFailure.transient(message)
        case .decoding, .invalidResponse:
            return DriverProfileFailure.server("The server response could not be read.")
        }
    }
}
