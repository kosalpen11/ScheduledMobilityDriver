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

    public init(
        loadHomeSnapshot: LoadHomeSnapshotUseCase,
        setAvailability: SetAvailabilityUseCase
    ) {
        self.loadHomeSnapshot = loadHomeSnapshot
        self.setAvailability = setAvailability
    }

    public func makeHome(onOutput: @escaping (HomeOutput) -> Void) -> UIViewController {
        let model = HomeViewModel(
            loadHomeSnapshot: loadHomeSnapshot,
            setAvailability: setAvailability
        )
        return HomeViewController(model: model, onOutput: onOutput)
    }
}
