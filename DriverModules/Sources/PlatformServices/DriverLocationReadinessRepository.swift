//
//  DriverLocationReadinessRepository.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/7/26.
//

import CoreLocation
import DriverDomain
import Foundation

@MainActor
public final class CoreLocationReadinessRepository: NSObject, DriverLocationReadinessRepository {
    private let manager = CLLocationManager()

    public override init() {
        super.init()
    }

    public func readiness() -> DriverLocationReadiness {
        DriverLocationReadiness(
            servicesEnabled: CLLocationManager.locationServicesEnabled(),
            authorizationStatus: mapStatus(CLLocationManager.authorizationStatus())
        )
    }

    public func requestAuthorizationIfNeeded() -> DriverLocationReadiness {
        let current = readiness()
        guard current.servicesEnabled, current.authorizationStatus == .notDetermined else {
            return current
        }
        if #available(iOS 8.0, macOS 10.15, *) {
            manager.requestWhenInUseAuthorization()
        }
        return readiness()
    }

    private func mapStatus(_ status: CLAuthorizationStatus) -> DriverLocationAuthorizationStatus {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .restricted:
            return .restricted
        case .denied:
            return .denied
        case .authorizedAlways:
            return .authorizedAlways
        case .authorizedWhenInUse:
            return .authorizedWhenInUse
        @unknown default:
            return .restricted
        }
    }
}