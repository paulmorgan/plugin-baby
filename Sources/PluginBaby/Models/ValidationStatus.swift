import SwiftUI

/// Result of running Apple's `auval` validator on an Audio Unit.
enum ValidationStatus: Equatable {
    case unknown          // not validated yet
    case running          // validation in progress
    case passed
    case failed
    case notApplicable    // not an Audio Unit (auval only covers AUs)

    var label: String {
        switch self {
        case .unknown: return "Not validated"
        case .running: return "Validating…"
        case .passed: return "Validated"
        case .failed: return "Failed validation"
        case .notApplicable: return "—"
        }
    }

    var symbol: String {
        switch self {
        case .unknown: return "questionmark.circle"
        case .running: return "clock"
        case .passed: return "checkmark.seal.fill"
        case .failed: return "xmark.octagon.fill"
        case .notApplicable: return "minus.circle"
        }
    }

    var color: Color {
        switch self {
        case .passed: return Color(red: 0.3, green: 0.9, blue: 0.55)
        case .failed: return Theme.accentSecondary
        case .running: return Theme.accent
        default: return Theme.textSecondary
        }
    }
}
