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

    private let loadHomeSnapshot: LoadHomeSnapshotUseCase
    private let setAvailability: SetAvailabilityUseCase
    private var refreshTask: Task<Void, Never>?

    public init(
        loadHomeSnapshot: LoadHomeSnapshotUseCase,
        setAvailability: SetAvailabilityUseCase
    ) {
        self.loadHomeSnapshot = loadHomeSnapshot
        self.setAvailability = setAvailability
        self.state = .initial
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
                let snapshot = try await loadHomeSnapshot()
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
