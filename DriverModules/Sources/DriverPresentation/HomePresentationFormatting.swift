//
//  HomePresentationFormatting.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/4/26.
//

import DriverDomain
import Foundation

public enum HomePresentationFormatting {
    public static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    public static func title(for availability: DriverAvailability) -> String {
        switch availability {
        case .available:
            return "Available"
        case .unavailable:
            return "Unavailable"
        }
    }

    public static func title(for assignment: TripAssignment) -> String {
        switch assignment {
        case .primary:
            return "Primary"
        case .backup:
            return "Backup"
        }
    }

    public static func title(for action: TripAction) -> String {
        switch action {
        case .viewDetails:
            return "View details"
        case .startPickup:
            return "Start pickup"
        case .markArrived:
            return "Mark arrived"
        case .startTrip:
            return "Start trip"
        case .completeTrip:
            return "Complete trip"
        }
    }

    public static func title(for status: TripStatus) -> String {
        switch status {
        case .scheduled:
            return "Scheduled"
        case .enRouteToPickup:
            return "En route"
        case .arrivedAtPickup:
            return "At pickup"
        case .inProgress:
            return "In progress"
        case .completed:
            return "Completed"
        case .cancelled:
            return "Cancelled"
        case .reassigned:
            return "Reassigned"
        }
    }
}
