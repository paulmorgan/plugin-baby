import SwiftUI

/// Visual identity: an electric, neon-on-dark palette evoking a plugged-in,
/// high-voltage feel. Original styling — not based on any band's artwork.
enum Theme {
    /// Electric cyan — primary accent.
    static let accent = Color(red: 0.0, green: 0.80, blue: 1.0)
    /// Hot magenta — secondary accent / highlights.
    static let accentSecondary = Color(red: 1.0, green: 0.18, blue: 0.62)

    // MARK: Surfaces (dark neon)
    static let background = Color(red: 0.035, green: 0.047, blue: 0.09)
    static let backgroundRaised = Color(red: 0.06, green: 0.075, blue: 0.13)
    static let panel = Color(red: 0.07, green: 0.09, blue: 0.145)
    static let cardFill = Color(red: 0.09, green: 0.11, blue: 0.17)
    static let cardFillSelected = Color(red: 0.07, green: 0.14, blue: 0.19)
    static let hairline = Color.white.opacity(0.07)

    static let textPrimary = Color(white: 0.96)
    static let textSecondary = Color(white: 0.62)

    static let wordmark = "PLUGIN BABY"
    static let tagline = "THE PLUGGED-IN COLLECTION"
    static let legacyWordmark = "PLUG·IN·BABY"

    /// Gradient used behind the wordmark / accents.
    static var brandGradient: LinearGradient {
        LinearGradient(
            colors: [accent, accentSecondary],
            startPoint: .leading, endPoint: .trailing)
    }

    static var brandGradientDiagonal: LinearGradient {
        LinearGradient(
            colors: [accent, accentSecondary],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Per-format accent used on badges and card glyphs.
    static func color(for format: PluginFormat) -> Color {
        switch format {
        case .audioUnit: return accent
        case .vst3: return Color(red: 0.55, green: 0.5, blue: 1.0)   // violet
        case .vst: return Color(red: 0.4, green: 0.85, blue: 0.7)    // teal-green
        case .clap: return accentSecondary
        }
    }
}

// MARK: - Reusable neon styling

/// A panel/card surface with a faint neon edge.
struct NeonPanel: ViewModifier {
    var selected: Bool = false
    var cornerRadius: CGFloat = 12
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(selected ? Theme.cardFillSelected : Theme.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        selected
                            ? AnyShapeStyle(Theme.accent.opacity(0.9))
                            : AnyShapeStyle(Theme.hairline),
                        lineWidth: selected ? 1.5 : 1)
            )
            .shadow(color: selected ? Theme.accent.opacity(0.35) : .clear,
                    radius: selected ? 10 : 0)
    }
}

extension View {
    func neonPanel(selected: Bool = false, cornerRadius: CGFloat = 12) -> some View {
        modifier(NeonPanel(selected: selected, cornerRadius: cornerRadius))
    }

    /// A soft neon glow around any view.
    func neonGlow(_ color: Color, radius: CGFloat = 6) -> some View {
        shadow(color: color.opacity(0.7), radius: radius)
    }
}
