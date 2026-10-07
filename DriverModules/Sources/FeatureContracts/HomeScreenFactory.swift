//
//  HomeScreenFactory.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/4/26.
//

import DriverDomain
import UIKit

public enum HomeOutput: Equatable {
    case showTrip(UUID)
    case showProfile
    case openProfile
}

@MainActor
public protocol HomeScreenFactory {
    func makeHome(onOutput: @escaping (HomeOutput) -> Void) -> UIViewController
}
