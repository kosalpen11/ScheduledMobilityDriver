//
//  DriverProfileUIKitScreenFactory.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/4/26.
//

import DriverDomain
import DriverPresentation
import FeatureContracts
import UIKit

public final class DriverProfileUIKitScreenFactory: DriverProfileScreenFactory {
    private let loadProfile: LoadDriverProfileUseCase
    private let loadDocuments: LoadDriverDocumentsUseCase
    private let uploadDocument: UploadDriverDocumentUseCase
    private let submitOnboarding: SubmitDriverOnboardingUseCase

    public init(
        loadProfile: LoadDriverProfileUseCase,
        loadDocuments: LoadDriverDocumentsUseCase,
        uploadDocument: UploadDriverDocumentUseCase,
        submitOnboarding: SubmitDriverOnboardingUseCase
    ) {
        self.loadProfile = loadProfile
        self.loadDocuments = loadDocuments
        self.uploadDocument = uploadDocument
        self.submitOnboarding = submitOnboarding
    }

    public func makeDriverProfile(onOutput: @escaping (DriverProfileOutput) -> Void) -> UIViewController {
        let model = DriverProfileViewModel(
            loadProfile: loadProfile,
            loadDocuments: loadDocuments,
            uploadDocument: uploadDocument,
            submitOnboarding: submitOnboarding
        )
        return DriverProfileViewController(model: model, loadDocuments: loadDocuments, onOutput: onOutput)
    }

    public func makeDriverProfileSummary(onOutput: @escaping (DriverProfileSummaryOutput) -> Void) -> UIViewController {
        let model = DriverProfileViewModel(
            loadProfile: loadProfile,
            loadDocuments: loadDocuments,
            uploadDocument: uploadDocument,
            submitOnboarding: submitOnboarding
        )
        return DriverProfileSummaryViewController(model: model, onOutput: onOutput)
    }
}
