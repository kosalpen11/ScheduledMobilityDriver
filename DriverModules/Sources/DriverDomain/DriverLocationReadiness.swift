//
//  DriverLocationReadiness.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/7/26.
//

import Foundation

public enum DriverLocationAuthorizationStatus: Equatable, Sendable {
    case notDetermined
    case denied
    case restricted
    case authorizedWhenInUse
    case authorizedAlways
}

public struct DriverLocationReadiness: Equatable, Sendable {
    public let servicesEnabled: Bool
    public let authorizationStatus: DriverLocationAuthorizationStatus

    public init(servicesEnabled: Bool, authorizationStatus: DriverLocationAuthorizationStatus) {
        self.servicesEnabled = servicesEnabled
        self.authorizationStatus = authorizationStatus
    }

    public var isAuthorized: Bool {
        switch authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return true
        case .notDetermined, .denied, .restricted:
            return false
        }
    }

    public var isReadyForDriverAvailability: Bool {
        servicesEnabled && isAuthorized
    }
}

@MainActor
public protocol DriverLocationReadinessRepository {
    func readiness() -> DriverLocationReadiness
    func requestAuthorizationIfNeeded() -> DriverLocationReadiness
}