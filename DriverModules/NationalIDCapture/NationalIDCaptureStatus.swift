//
//  NationalIDCaptureStatus.swift
//  ScheduledMobilityDriver
//

enum NationalIDCaptureStatus: String {
    case noDocument
    case tooSmall
    case tooLarge
    case unstable
    case glare
    case blurry
    case invalidShape
    case wrongOrientation
    case align
    case ready

    var message: String {
        switch self {
        case .noDocument:
            return "Place your National ID inside the frame"
        case .tooSmall:
            return "Move closer to the card"
        case .tooLarge:
            return "Move back a little"
        case .unstable:
            return "Hold the phone steady"
        case .glare:
            return "Tilt the card to reduce glare"
        case .blurry:
            return "Hold steady for a clearer photo"
        case .invalidShape:
            return "Align the whole National ID"
        case .wrongOrientation:
            return "Turn the card to landscape"
        case .align:
            return "Place the whole National ID inside the center frame"
        case .ready:
            return "Hold steady"
        }
    }
}
