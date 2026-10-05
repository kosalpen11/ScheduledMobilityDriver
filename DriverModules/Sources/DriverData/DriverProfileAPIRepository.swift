//
//  DriverProfileAPIRepository.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/4/26.
//

import DriverDomain
import Foundation
import PlatformServices

public final class DriverProfileAPIRepository: DriverProfileRepository, @unchecked Sendable {
    private let auth: AuthAPIRepository
    private let validator: DriverDocumentUploadValidator
    private let dateFormatter: DateFormatter

    public init(
        auth: AuthAPIRepository,
        validator: DriverDocumentUploadValidator = DriverDocumentUploadValidator()
    ) {
        self.auth = auth
        self.validator = validator
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        self.dateFormatter = formatter
    }

    public func loadProfile() async throws -> DriverProfileDetail {
        do {
            let dto: DriverProfileDetailDTO = try await auth.authenticatedSend(
                "GET",
                path: "drivers/me",
                body: Optional<EmptyBody>.none
            )
            return dto.domain()
        } catch {
            throw DriverProfileErrorMapper.map(error)
        }
    }

    public func loadDocuments() async throws -> [DriverDocument] {
        do {
            let dto: [DriverDocumentDTO] = try await auth.authenticatedSend(
                "GET",
                path: "drivers/me/documents",
                body: Optional<EmptyBody>.none
            )
            return dto.map { $0.domain() }
        } catch {
            throw DriverProfileErrorMapper.map(error)
        }
    }

    public func uploadDocument(_ upload: DriverDocumentUpload) async throws -> DriverDocument {
        do {
            let kind = try validator.validate(upload)
            var parts: [MultipartFormPart] = [
                MultipartFormPart(name: "type", data: Data(upload.type.rawValue.utf8)),
                MultipartFormPart(
                    name: "file",
                    filename: upload.filename,
                    contentType: kind.contentType,
                    data: upload.content
                )
            ]
            if let vehicleID = upload.vehicleID {
                parts.append(MultipartFormPart(name: "vehicleId", data: Data(vehicleID.uuidString.utf8)))
            }
            if let expiresOn = upload.expiresOn {
                parts.append(MultipartFormPart(name: "expiresOn", data: Data(dateFormatter.string(from: expiresOn).utf8)))
            }

            let dto: DriverDocumentDTO = try await auth.authenticatedMultipartSend(
                "POST",
                path: "drivers/me/documents",
                parts: parts,
                headers: ["Idempotency-Key": UUID().uuidString]
            )
            return dto.domain()
        } catch {
            throw DriverProfileErrorMapper.map(error)
        }
    }

    public func submitOnboarding() async throws -> DriverProfileDetail {
        do {
            let dto: DriverProfileDetailDTO = try await auth.authenticatedSend(
                "POST",
                path: "drivers/me/submit",
                body: Optional<EmptyBody>.none,
                headers: ["Idempotency-Key": UUID().uuidString]
            )
            return dto.domain()
        } catch {
            throw DriverProfileErrorMapper.map(error)
        }
    }

    public func clearSessionState() async {}
}
