@testable import DriverData
import DriverDomain
import Foundation
import PlatformServices
import XCTest

final class DriverProfileAPIRepositoryTests: XCTestCase {
    func testNationalIDUploadUsesPostmanFrontAndBackMultipartFields() async throws {
        let transport = CapturingHTTPTransport(responseBody: Data("""
        {
          "id": "0E5177EE-09A0-4000-B3E2-2AFCA700FF93",
          "type": "NATIONAL_ID",
          "vehicleId": null,
          "status": "PENDING_REVIEW",
          "files": [
            { "contentType": "image/jpeg", "side": "FRONT", "sizeBytes": 3 },
            { "contentType": "image/jpeg", "side": "BACK", "sizeBytes": 3 }
          ],
          "expiresOn": "2028-10-06",
          "uploadedAt": "2026-10-06T13:46:21.699497Z",
          "reviewedAt": null,
          "rejectionReason": null,
          "expiryFlaggedAt": null
        }
        """.utf8))
        let client = HTTPClient(baseURL: URL(string: "https://api.example.test")!, transport: transport)
        let tokens = AuthTokens(
            accessToken: "access",
            tokenType: "Bearer",
            expiresInSeconds: 3600,
            refreshToken: "refresh",
            refreshExpiresInSeconds: 7200
        )
        let auth = AuthAPIRepository(client: client, tokenStorage: InMemoryTokenStorage(tokens: tokens))
        let repository = DriverProfileAPIRepository(auth: auth)
        let jpeg = Data([0xFF, 0xD8, 0xFF])

        _ = try await repository.uploadDocument(
            DriverDocumentUpload(
                type: .nationalID,
                vehicleID: nil,
                expiresOn: Date(timeIntervalSince1970: 1_854_489_600),
                files: [
                    DriverDocumentUploadFile(fieldName: "front", filename: "front.jpg", content: jpeg),
                    DriverDocumentUploadFile(fieldName: "back", filename: "back.jpg", content: jpeg)
                ]
            )
        )

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/drivers/me/documents")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access")
        let body = String(data: try XCTUnwrap(request.httpBody), encoding: .utf8)
        XCTAssertTrue(try XCTUnwrap(body).contains("name=\"front\"; filename=\"front.jpg\""))
        XCTAssertTrue(try XCTUnwrap(body).contains("name=\"back\"; filename=\"back.jpg\""))
        XCTAssertFalse(try XCTUnwrap(body).contains("name=\"file\""))
        XCTAssertTrue(try XCTUnwrap(body).contains("name=\"type\""))
        XCTAssertTrue(try XCTUnwrap(body).contains("NATIONAL_ID"))
        XCTAssertTrue(try XCTUnwrap(body).contains("name=\"expiresOn\""))
        XCTAssertTrue(try XCTUnwrap(body).contains("2028-10-06"))
    }
}

private final class CapturingHTTPTransport: HTTPTransport, @unchecked Sendable {
    private let responseBody: Data
    private(set) var requests: [URLRequest] = []

    init(responseBody: Data) {
        self.responseBody = responseBody
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (responseBody, response)
    }
}
