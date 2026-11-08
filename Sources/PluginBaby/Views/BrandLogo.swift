import SwiftUI

/// Original neon plug mark — a glowing cable + plug, drawn in code. Echoes the
/// app icon. Not based on any band's artwork.
struct PlugMark: View {
    var size: CGFloat = 34

    var body: some View {
        Canvas { ctx, rect in
            let s = rect.width
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }

            // Magenta glowing cable.
            var cable = Path()
            cable.move(to: p(0.20, 0.30))
            cable.addCurve(to: p(0.58, 0.44),
                           control1: p(0.30, 0.86), control2: p(0.62, 0.74))
            ctx.addFilter(.shadow(color: Theme.accentSecondary.opacity(0.9), radius: s * 0.08))
            ctx.stroke(cable, with: .color(Theme.accentSecondary),
                       style: StrokeStyle(lineWidth: s * 0.07, lineCap: .round))

            // Cyan glowing plug body + prongs.
            ctx.addFilter(.shadow(color: Theme.accent.opacity(0.9), radius: s * 0.07))
            let body = Path(roundedRect: CGRect(x: 0.50 * s, y: 0.30 * s,
                                                width: 0.20 * s, height: 0.16 * s),
                            cornerRadius: s * 0.03)
            ctx.fill(body, with: .color(Theme.accent))
            var prongs = Path()
            prongs.move(to: p(0.70, 0.345)); prongs.addLine(to: p(0.82, 0.345))
            prongs.move(to: p(0.70, 0.415)); prongs.addLine(to: p(0.82, 0.415))
            ctx.stroke(prongs, with: .color(Theme.accent),
                       style: StrokeStyle(lineWidth: s * 0.035, lineCap: .round))
        }
        .frame(width: size, height: size)
    }
}

/// Sidebar brand block: plug mark + wordmark.
struct SidebarBrand: View {
    var body: some View {
        HStack(spacing: 10) {
            PlugMark(size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(Theme.wordmark)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.brandGradient)
                Text(Theme.tagline)
                    .font(.system(size: 8, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }
}
