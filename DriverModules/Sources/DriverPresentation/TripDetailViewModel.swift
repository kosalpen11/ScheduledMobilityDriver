//
//  TripDetailViewModel.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/5/26.
//

import DriverDomain
import Foundation

@MainActor
public final class TripDetailViewModel: ObservableObject {
    public enum State: Equatable {
        case initial
        case loading
        case content(TripDetailPresentation)
        case refreshing(TripDetailPresentation)
        case actionInFlight(TripDetailPresentation)
        case recoverableError(TripDetailPresentation, String)
        case failure(String)
    }

    @Published public private(set) var state: State = .initial

    private let tripID: UUID
    private let loadTrip: LoadTripDetailUseCase
    private let performAction: PerformTripActionUseCase
    private let resolver = TripActionResolver()
    private var inFlightActionKey: String?

    public init(
        tripID: UUID,
        loadTrip: LoadTripDetailUseCase,
        performAction: PerformTripActionUseCase
    ) {
        self.tripID = tripID
        self.loadTrip = loadTrip
        self.performAction = performAction
    }

    public func load() async {
        if let presentation = state.presentation {
            state = .refreshing(presentation)
        } else {
            state = .loading
        }

        do {
            apply(try await loadTrip(id: tripID))
        } catch {
            fail(error)
        }
    }

    public func performPrimaryAction() async -> Bool {
        guard inFlightActionKey == nil, let presentation = state.presentation, presentation.primaryAction != .viewDetails else {
            return false
        }

        let key = "\(tripID.uuidString)-\(presentation.primaryAction)-\(presentation.version)"
        inFlightActionKey = key
        state = .actionInFlight(presentation)
        defer { inFlightActionKey = nil }

        do {
            let updated = try await performAction(
                TripActionRequest(
                    tripID: tripID,
                    action: presentation.primaryAction,
                    expectedVersion: presentation.version,
                    idempotencyKey: key
                )
            )
            apply(updated)
            return true
        } catch TripFailure.conflict(let message),
                TripFailure.cancelled(let message),
                TripFailure.reassigned(let message) {
            await load()
            if let refreshed = state.presentation {
                state = .recoverableError(refreshed, message)
            }
            return false
        } catch {
            fail(error)
            return false
        }
    }

    private func apply(_ trip: ScheduledTrip) {
        let action = resolver.nextAction(for: trip)
        state = .content(TripDetailPresentation(trip: trip, primaryAction: action, canPerformPrimaryAction: resolver.isActionPermitted(action, for: trip)))
    }

    private func fail(_ error: Error) {
        let message = Self.message(for: error)
        if let presentation = state.presentation {
            state = .recoverableError(presentation, message)
        } else {
            state = .failure(message)
        }
    }

    private static func message(for error: Error) -> String {
        if let failure = error as? TripFailure {
            switch failure {
            case .unavailable(let message),
                 .notPermitted(let message),
                 .conflict(let message),
                 .cancelled(let message),
                 .reassigned(let message),
                 .transient(let message),
                 .server(let message):
                return message
            }
        }
        return "Could not update the trip. Pull to refresh and try again."
    }
}

public struct TripDetailPresentation: Equatable {
    public let trip: ScheduledTrip
    public let primaryAction: TripAction
    public let canPerformPrimaryAction: Bool

    public var version: Int { trip.version }

    public init(trip: ScheduledTrip, primaryAction: TripAction, canPerformPrimaryAction: Bool) {
        self.trip = trip
        self.primaryAction = primaryAction
        self.canPerformPrimaryAction = canPerformPrimaryAction
    }
}

public extension TripDetailViewModel.State {
    var presentation: TripDetailPresentation? {
        switch self {
        case .content(let presentation),
             .refreshing(let presentation),
             .actionInFlight(let presentation),
             .recoverableError(let presentation, _):
            return presentation
        case .initial, .loading, .failure:
            return nil
        }
    }

    var isBusy: Bool {
        switch self {
        case .loading, .refreshing, .actionInFlight:
            return true
        case .initial, .content, .recoverableError, .failure:
            return false
        }
    }
}
