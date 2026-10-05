//
//  AuthScreenFactory.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/4/26.
//

import DriverDomain
import UIKit

public enum AuthOutput: Equatable {
    case authenticated(AuthenticatedSession)
    case developmentHomeBypass
}

@MainActor
public protocol AuthScreenFactory {
    func makeAuth(onOutput: @escaping (AuthOutput) -> Void) -> UIViewController
}
