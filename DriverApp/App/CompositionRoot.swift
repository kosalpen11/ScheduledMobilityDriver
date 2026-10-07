//
//  CompositionRoot.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/4/26.
//

import DriverData
import DriverDomain
import DriverSwiftUI
import DriverUIKit
import FeatureContracts
import PlatformServices
import UIKit

@MainActor
final class CompositionRoot {
    private let configuration: APIConfiguration
    private let authRepository: any AuthRepository
    private let driverProfileRepository: any DriverProfileRepository
    private let tripRepository: any TripRepository
    private let availabilityRepository: any AvailabilityRepository

    init(configuration: APIConfiguration) {
        self.configuration = configuration
        if let baseURL = configuration.baseURL, configuration.environment != .mock {
            let client = HTTPClient(baseURL: baseURL, logger: Self.makeHTTPLogger(for: configuration))
            let authAPI = AuthAPIRepository(
                client: client,
                tokenStorage: KeychainTokenStorage()
            )
            self.authRepository = authAPI
            self.driverProfileRepository = DriverProfileAPIRepository(auth: authAPI)
        } else if configuration.environment == .mock {
            let auth = MockAuthRepository()
            self.authRepository = auth
            self.driverProfileRepository = MockDriverProfileRepository()
        } else {
            preconditionFailure("Non-mock driver runtime requires an API base URL.")
        }
        if configuration.environment == .mock {
            self.tripRepository = MockTripRepository()
            self.availabilityRepository = MockAvailabilityRepository()
        } else {
            self.tripRepository = UnavailableTripRepository()
            self.availabilityRepository = UnavailableAvailabilityRepository()
        }
    }

    func makeRestoreSessionUseCase() -> RestoreSessionUseCase {
        RestoreSessionUseCase(repository: authRepository)
    }

    func makeLogoutUseCase() -> LogoutUseCase {
        LogoutUseCase(repository: authRepository)
    }

    func makeClearDriverSessionUseCase() -> ClearDriverSessionUseCase {
        ClearDriverSessionUseCase(repository: driverProfileRepository)
    }

    func makeLoadDriverProfileUseCase() -> LoadDriverProfileUseCase {
        LoadDriverProfileUseCase(repository: driverProfileRepository)
    }

    func makeAuthFactory() -> any AuthScreenFactory {
        AuthSwiftUIScreenFactory(
            requestOTP: RequestOTPUseCase(repository: authRepository),
            verifyOTP: VerifyOTPUseCase(repository: authRepository),
            allowsDevelopmentBypass: allowsDevelopmentBypass
        )
    }

    func makeHomeFactory() -> any HomeScreenFactory {
        let loadHomeSnapshot = LoadHomeSnapshotUseCase(
            trips: tripRepository,
            availability: availabilityRepository
        )
        let setAvailability = SetAvailabilityUseCase(repository: availabilityRepository)

        return HomeSwiftUIScreenFactory(
            loadHomeSnapshot: loadHomeSnapshot,
            setAvailability: setAvailability,
            loadDriverProfile: LoadDriverProfileUseCase(repository: driverProfileRepository)
        )
    }

    func makeDriverProfileFactory() -> any DriverProfileScreenFactory {
        DriverProfileUIKitScreenFactory(
            loadProfile: LoadDriverProfileUseCase(repository: driverProfileRepository),
            uploadDocument: UploadDriverDocumentUseCase(repository: driverProfileRepository),
            submitOnboarding: SubmitDriverOnboardingUseCase(repository: driverProfileRepository)
        )
    }

    func makeDriverEntryFactory() -> any DriverEntryScreenFactory {
        DriverEntrySwiftUIScreenFactory()
    }

    func makeTripFactory() -> any TripScreenFactory {
        TripUIKitScreenFactory(
            loadTrip: LoadTripDetailUseCase(repository: tripRepository),
            performAction: PerformTripActionUseCase(repository: tripRepository)
        )
    }

    private static func makeHTTPLogger(for configuration: APIConfiguration) -> (any HTTPLogger)? {
        #if DEBUG
        return configuration.environment == .staging ? ConsoleHTTPLogger() : nil
        #else
        return nil
        #endif
    }

    private var allowsDevelopmentBypass: Bool {
        #if DEBUG
        return configuration.environment == .staging
        #else
        return false
        #endif
    }
}
