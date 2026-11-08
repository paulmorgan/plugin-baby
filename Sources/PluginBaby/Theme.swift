import SwiftUI

/// Visual identity: an electric, neon-on-dark palette evoking a plugged-in,
/// high-voltage feel. Original styling — not based on any band's artwork.
enum Theme {
    /// Electric cyan — primary accent.
    static let accent = Color(red: 0.0, green: 0.80, blue: 1.0)
    /// Hot magenta — secondary accent / highlights.
    static let accentSecondary = Color(red: 1.0, green: 0.18, blue: 0.62)

    static let wordmark = "PLUG·IN·BABY"
    static let tagline = "audio plugin manager"

    /// Gradient used behind the wordmark.
    static var brandGradient: LinearGradient {
        LinearGradient(
            colors: [accent, accentSecondary],
            startPoint: .leading, endPoint: .trailing)
    }
}
