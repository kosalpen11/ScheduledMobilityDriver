//
//  DriverProfileScreenFactory.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/4/26.
//

import DriverDomain
import UIKit

public enum DriverProfileOutput: Equatable {
    case logoutRequested
}

public enum DriverProfileSummaryOutput: Equatable {
    case viewProfile
    case logoutRequested
}

@MainActor
public protocol DriverProfileScreenFactory {
    func makeDriverProfile(onOutput: @escaping (DriverProfileOutput) -> Void) -> UIViewController
    func makeDriverProfileSummary(onOutput: @escaping (DriverProfileSummaryOutput) -> Void) -> UIViewController
}
