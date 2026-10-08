//
//  HomeViewModel.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/4/26.
//

import Combine
import DriverDomain
import Foundation

@MainActor
public final class HomeViewModel: ObservableObject {
    @Published public private(set) var state: HomeViewState
    @Published public private(set) var profileGate: HomeProfileGate

    private let loadHomeSnapshot: LoadHomeSnapshotUseCase
    private let setAvailability: SetAvailabilityUseCase
    private let loadDriverProfile: LoadDriverProfileUseCase?
    private let locationReadinessRepository: (any DriverLocationReadinessRepository)?
    private let eligibility = DriverEligibilityPolicy()
    private var refreshTask: Task<Void, Never>?

    public init(
        loadHomeSnapshot: LoadHomeSnapshotUseCase,
        setAvailability: SetAvailabilityUseCase,
        loadDriverProfile: LoadDriverProfileUseCase? = nil,
        locationReadinessRepository: (any DriverLocationReadinessRepository)? = nil
    ) {
        self.loadHomeSnapshot = loadHomeSnapshot
        self.setAvailability = setAvailability
        self.loadDriverProfile = loadDriverProfile
        self.locationReadinessRepository = locationReadinessRepository
        self.state = .initial
        self.profileGate = .allowed
    }

    deinit {
        refreshTask?.cancel()
    }

    public func load() {
        guard refreshTask == nil else { return }
        transitionToLoading()

        refreshTask = Task { [weak self] in
            guard let self else { return }
            do {
                let gate = await loadProfileGate()
                guard !Task.isCancelled else { return }
                profileGate = gate
                let snapshot = try await loadHomeSnapshot(availabilityOverride: gate.allowsAvailability ? nil : .unavailable)
                guard !Task.isCancelled else { return }
                state = snapshot.trips.isEmpty ? .empty(snapshot) : .content(snapshot)
            } catch {
                guard !Task.isCancelled else { return }
                state = state.contentSnapshot.map { .refreshFailed($0, message: Self.message(for: error)) }
                    ?? .failure(Self.message(for: error))
            }
            refreshTask = nil
        }
    }

    public func refresh() {
        refreshTask?.cancel()
        refreshTask = nil
        load()
    }

    public func toggleAvailability() {
        guard profileGate.allowsAvailability else { return }
        guard let current = state.contentSnapshot?.availability else { return }
        let target: DriverAvailability = current == .available ? .unavailable : .available
        let priorState = state
        state = .updatingAvailability(priorState.contentSnapshot!)

        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await setAvailability(target)
                refresh()
            } catch {
                state = priorState.contentSnapshot.map {
                    .refreshFailed($0, message: Self.message(for: error))
                } ?? priorState
            }
        }
    }

    public func requestLocationAuthorizationIfNeeded() {
        guard let locationReadinessRepository else { return }
        _ = locationReadinessRepository.requestAuthorizationIfNeeded()
        refresh()
    }

    private func loadProfileGate() async -> HomeProfileGate {
        guard let loadDriverProfile else {
            return locationGate()
        }
        do {
            let profile = try await loadDriverProfile()
            guard eligibility.canOperate(profile) else {
                return .blocked(
                    title: title(for: profile),
                    detail: detail(for: profile),
                    actionTitle: "Complete profile",
                    action: .openProfile
                )
            }
            return locationGate()
        } catch {
            return .blocked(
                title: "Profile check needed",
                detail: Self.message(for: error),
                actionTitle: "Open profile",
                action: .openProfile
            )
        }
    }

    private func locationGate() -> HomeProfileGate {
        guard let locationReadinessRepository else {
            return .allowed
        }
        let readiness = locationReadinessRepository.readiness()
        guard readiness.servicesEnabled else {
            return .blocked(
                title: "Turn on location services",
                detail: "Location Services must be enabled to receive taxi assignments.",
                actionTitle: "Open settings",
                action: .openLocationSettings
            )
        }

        switch readiness.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return .allowed
        case .notDetermined:
            return .blocked(
                title: "Location permission required",
                detail: "Allow location access so dispatch can match nearby trips.",
                actionTitle: "Allow location",
                action: .requestLocationPermission
            )
        case .denied, .restricted:
            return .blocked(
                title: "Location access blocked",
                detail: "Enable location access in Settings to go available.",
                actionTitle: "Open settings",
                action: .openLocationSettings
            )
        }
    }

    private func title(for profile: DriverProfileDetail) -> String {
        switch profile.status {
        case .pending:
            return "Complete driver profile"
        case .documentsSubmitted:
            return "Documents under review"
        case .training:
            return "Training required"
        case .approved:
            return "Driver requirements pending"
        case .rejected:
            return "Profile needs attention"
        case .suspended:
            return "Account restricted"
        case .unknown:
            return "Profile check needed"
        }
    }

    private func detail(for profile: DriverProfileDetail) -> String {
        switch profile.status {
        case .pending:
            if let missing = profile.readiness.missing.first {
                return "\(missing.displayTitle) is required before you can go available."
            }
            if profile.readiness.pendingReview.isEmpty == false {
                return "Your uploaded documents need review before you can go available."
            }
            return "Submit your driver documents before going available."
        case .documentsSubmitted:
            return "Your documents are with the operations team. Availability is disabled until approval is complete."
        case .training:
            return "Complete training before going available."
        case .approved:
            if profile.readiness.hasActiveVehicle == false {
                return "An active vehicle assignment is required before you can go available."
            }
            if let expired = profile.readiness.expired.first {
                return "\(expired.displayTitle) has expired. Replace it before going available."
            }
            if let pending = profile.readiness.pendingReview.first {
                return "\(pending.displayTitle) is still under review."
            }
            if let missing = profile.readiness.missing.first {
                return "\(missing.displayTitle) is required before you can go available."
            }
            return "Review your profile requirements before going available."
        case .rejected:
            return "Your driver profile needs attention before availability can be enabled."
        case .suspended:
            return "Driver availability is disabled while the account is restricted."
        case .unknown:
            return "Open your profile to check driver requirements."
        }
    }

    private func transitionToLoading() {
        if let snapshot = state.contentSnapshot {
            state = .refreshing(snapshot)
        } else {
            state = .loading
        }
    }

    private static func message(for error: Error) -> String {
        if error is CancellationError {
            return "Request cancelled."
        }
        if case TripFailure.unavailable(let message) = error {
            return message
        }
        if case TripFailure.transient(let message) = error {
            return message
        }
        if case TripFailure.server(let message) = error {
            return message
        }
        return "Could not reach the driver service. Pull to try again."
    }
}

public enum HomeProfileGate: Equatable {
    case allowed
    case blocked(title: String, detail: String, actionTitle: String, action: HomeProfileAction)

    public var allowsAvailability: Bool {
        self == .allowed
    }

    public var prompt: HomeProfilePrompt? {
        switch self {
        case .allowed:
            return nil
        case .blocked(let title, let detail, let actionTitle, let action):
            return HomeProfilePrompt(title: title, detail: detail, actionTitle: actionTitle, action: action)
        }
    }
}

public enum HomeProfileAction: Equatable {
    case openProfile
    case requestLocationPermission
    case openLocationSettings
}

public struct HomeProfilePrompt: Equatable {
    public let title: String
    public let detail: String
    public let actionTitle: String
    public let action: HomeProfileAction

    public init(title: String, detail: String, actionTitle: String, action: HomeProfileAction) {
        self.title = title
        self.detail = detail
        self.actionTitle = actionTitle
        self.action = action
    }
}

public enum HomeViewState: Equatable {
    case initial
    case loading
    case content(HomeSnapshot)
    case empty(HomeSnapshot)
    case refreshing(HomeSnapshot)
    case updatingAvailability(HomeSnapshot)
    case refreshFailed(HomeSnapshot, message: String)
    case failure(String)

    public var contentSnapshot: HomeSnapshot? {
        switch self {
        case .content(let snapshot),
             .empty(let snapshot),
             .refreshing(let snapshot),
             .updatingAvailability(let snapshot),
             .refreshFailed(let snapshot, _):
            return snapshot
        case .initial, .loading, .failure:
            return nil
        }
    }

    public var isBusy: Bool {
        switch self {
        case .loading, .refreshing, .updatingAvailability:
            return true
        case .initial, .content, .empty, .refreshFailed, .failure:
            return false
        }
    }
}
