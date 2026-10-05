//
//  TripUIKitScreenFactory.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/5/26.
//

import DriverDomain
import DriverPresentation
import FeatureContracts
import UIKit

public final class TripUIKitScreenFactory: TripScreenFactory {
    private let loadTrip: LoadTripDetailUseCase
    private let performAction: PerformTripActionUseCase

    public init(loadTrip: LoadTripDetailUseCase, performAction: PerformTripActionUseCase) {
        self.loadTrip = loadTrip
        self.performAction = performAction
    }

    public func makeTripDetail(id: UUID, onOutput: @escaping (TripOutput) -> Void) -> UIViewController {
        let model = TripDetailViewModel(tripID: id, loadTrip: loadTrip, performAction: performAction)
        return TripDetailViewController(model: model, onOutput: onOutput)
    }
}
