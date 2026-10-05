//
//  TripScreenFactory.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/5/26.
//

import Foundation
import UIKit

public enum TripOutput: Equatable {
    case tripChanged
}

@MainActor
public protocol TripScreenFactory {
    func makeTripDetail(id: UUID, onOutput: @escaping (TripOutput) -> Void) -> UIViewController
}
