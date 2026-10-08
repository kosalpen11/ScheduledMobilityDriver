import Foundation

public enum DriverLoadingState: Equatable, Sendable {
    case idle
    case initial
    case refreshing
    case reconnecting
    case performingAction
    case uploading(progress: Double?)

    public var isBusy: Bool {
        switch self {
        case .idle:
            return false
        case .initial, .refreshing, .reconnecting, .performingAction, .uploading:
            return true
        }
    }

    public var showsProgress: Bool {
        if case .uploading = self {
            return true
        }
        return false
    }

    public var progressFraction: Double? {
        if case .uploading(let value) = self {
            return value
        }
        return nil
    }
}
