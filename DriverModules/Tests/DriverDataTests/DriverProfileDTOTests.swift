//
//  DriverProfileDTOTests.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/4/26.
//

@testable import DriverData
import DriverDomain
import XCTest

final class DriverProfileDTOTests: XCTestCase {
    func testDriverProfileDTOMapsBackendReadinessVehicleAndDocuments() throws {
        let json = Data("""
        {
          "id": "2D6BE87F-3B46-41A2-A704-8C42B26E1E23",
          "userId": "8A11112D-98D3-4F2A-A420-F632F6156E26",
          "fullName": "Kosal Pen",
          "phone": "+85512000002",
          "status": "APPROVED",
          "nationalIdMasked": "********1234",
          "vehicle": {
            "id": "4F49638D-28F5-4CC7-B133-0F6A4BF87A80",
            "plateNumber": "2AB-146",
            "vehicleClass": "CAR",
            "make": "Toyota",
            "model": "Prius",
            "color": "White",
            "modelYear": 2017,
            "seats": 4,
            "status": "ACTIVE",
            "assignedAt": "2026-10-01T08:00:00Z"
          },
          "documents": [{
            "id": "0BE33D31-1072-4F90-8F60-58C131C9F0C0",
            "type": "DRIVING_LICENSE",
            "status": "PENDING_REVIEW",
            "contentType": "application/pdf",
            "sizeBytes": 1234,
            "expiresOn": "2028-03-01",
            "uploadedAt": "2026-10-02T09:12:00Z"
          }],
          "readiness": {
            "missing": ["VEHICLE_INSURANCE"],
            "pendingReview": ["DRIVING_LICENSE"],
            "expired": [],
            "hasActiveVehicle": true
          },
          "createdAt": "2026-10-01T08:00:00Z"
        }
        """.utf8)

        let dto = try JSONDecoder().decode(DriverProfileDetailDTO.self, from: json)
        let profile = dto.domain()

        XCTAssertEqual(profile.status, .approved)
        XCTAssertEqual(profile.vehicle?.vehicleClass, .car)
        XCTAssertEqual(profile.documents.first?.type, .drivingLicense)
        XCTAssertEqual(profile.readiness.missing, [.vehicleInsurance])
        XCTAssertEqual(profile.readiness.pendingReview, [.drivingLicense])
    }
}
