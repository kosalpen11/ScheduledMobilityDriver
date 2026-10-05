//
//  DriverProfileRepositories.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/4/26.
//

import Foundation

public protocol DriverProfileRepository: Sendable {
    func loadProfile() async throws -> DriverProfileDetail
    func loadDocuments() async throws -> [DriverDocument]
    func uploadDocument(_ upload: DriverDocumentUpload) async throws -> DriverDocument
    func submitOnboarding() async throws -> DriverProfileDetail
    func clearSessionState() async
}
