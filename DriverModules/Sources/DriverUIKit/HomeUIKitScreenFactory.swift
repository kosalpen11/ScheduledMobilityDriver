//
//  HomeUIKitScreenFactory.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/4/26.
//

import DriverPresentation
import DriverDomain
import FeatureContracts
import UIKit

public final class HomeUIKitScreenFactory: HomeScreenFactory {
    private let loadHomeSnapshot: LoadHomeSnapshotUseCase
    private let setAvailability: SetAvailabilityUseCase
    private let loadDriverProfile: LoadDriverProfileUseCase?

    public init(
        loadHomeSnapshot: LoadHomeSnapshotUseCase,
        setAvailability: SetAvailabilityUseCase,
        loadDriverProfile: LoadDriverProfileUseCase? = nil
    ) {
        self.loadHomeSnapshot = loadHomeSnapshot
        self.setAvailability = setAvailability
        self.loadDriverProfile = loadDriverProfile
    }

    public func makeHome(onOutput: @escaping (HomeOutput) -> Void) -> UIViewController {
        let model = HomeViewModel(
            loadHomeSnapshot: loadHomeSnapshot,
            setAvailability: setAvailability,
            loadDriverProfile: loadDriverProfile
        )
        return HomeViewController(model: model, onOutput: onOutput)
    }
}
