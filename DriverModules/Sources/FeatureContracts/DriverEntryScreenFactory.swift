//
//  DriverEntryScreenFactory.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/5/26.
//

import DriverDomain
import UIKit

public enum DriverEntryOutput: Equatable {
    case signOut
    case showOnboarding
    case retry
}

@MainActor
public protocol DriverEntryScreenFactory {
    func makeDriverEntryStatus(
        resolution: DriverEntryResolution,
        onOutput: @escaping (DriverEntryOutput) -> Void
    ) -> UIViewController
}
