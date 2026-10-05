//
//  DriverProfileUseCases.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/4/26.
//

import Foundation

public struct LoadDriverProfileUseCase: Sendable {
    private let repository: any DriverProfileRepository

    public init(repository: any DriverProfileRepository) {
        self.repository = repository
    }

    public func callAsFunction() async throws -> DriverProfileDetail {
        try await repository.loadProfile()
    }
}

public struct UploadDriverDocumentUseCase: Sendable {
    private let repository: any DriverProfileRepository
    private let validator: DriverDocumentUploadValidator

    public init(
        repository: any DriverProfileRepository,
        validator: DriverDocumentUploadValidator = DriverDocumentUploadValidator()
    ) {
        self.repository = repository
        self.validator = validator
    }

    @discardableResult
    public func callAsFunction(_ upload: DriverDocumentUpload) async throws -> DriverDocument {
        _ = try validator.validate(upload)
        return try await repository.uploadDocument(upload)
    }
}

public struct SubmitDriverOnboardingUseCase: Sendable {
    private let repository: any DriverProfileRepository

    public init(repository: any DriverProfileRepository) {
        self.repository = repository
    }

    public func callAsFunction() async throws -> DriverProfileDetail {
        try await repository.submitOnboarding()
    }
}

public struct ClearDriverSessionUseCase: Sendable {
    private let repository: any DriverProfileRepository

    public init(repository: any DriverProfileRepository) {
        self.repository = repository
    }

    public func callAsFunction() async {
        await repository.clearSessionState()
    }
}
