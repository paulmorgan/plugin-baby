import SwiftUI

/// Neon spectrum bars driven by the audition engine. When nothing is playing the
/// values are zero, so it rests as a quiet baseline.
struct SpectrumView: View {
    var bands: [Float]
    var active: Bool

    var body: some View {
        Canvas { ctx, rect in
            guard !bands.isEmpty else { return }
            let n = bands.count
            let gap: CGFloat = 2
            let barW = (rect.width - gap * CGFloat(n - 1)) / CGFloat(n)
            let baseline = rect.height
            for (i, raw) in bands.enumerated() {
                let v = CGFloat(max(0.02, min(1, raw)))
                let h = v * rect.height
                let x = CGFloat(i) * (barW + gap)
                let bar = Path(roundedRect: CGRect(x: x, y: baseline - h, width: barW, height: h),
                               cornerRadius: barW * 0.35)
                // Color shifts cyan→magenta across the spectrum.
                let t = Double(i) / Double(max(1, n - 1))
                let color = Color(
                    red: 0.0 + t,
                    green: 0.80 - 0.62 * t,
                    blue: 1.0 - 0.38 * t)
                if active { ctx.addFilter(.shadow(color: color.opacity(0.6), radius: 4)) }
                ctx.fill(bar, with: .color(color.opacity(active ? 0.95 : 0.35)))
            }
        }
        .animation(.linear(duration: 0.06), value: bands)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.background.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.hairline)
        )
    }
}

/// A single vertical neon level meter (peak, 0…1).
struct LevelMeterView: View {
    var level: Float
    var active: Bool
    var segments = 16

    var body: some View {
        GeometryReader { geo in
            let lit = Int((Float(segments) * min(max(level, 0), 1)).rounded())
            let segH = (geo.size.height - CGFloat(segments - 1) * 2) / CGFloat(segments)
            VStack(spacing: 2) {
                ForEach(0..<segments, id: \.self) { i in
                    let idx = segments - 1 - i   // top is loudest
                    let on = idx < lit && active
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(on ? segColor(idx) : Theme.hairline)
                        .frame(height: segH)
                        .shadow(color: on ? segColor(idx).opacity(0.7) : .clear, radius: 2)
                }
            }
        }
        .animation(.linear(duration: 0.06), value: level)
    }

    private func segColor(_ idx: Int) -> Color {
        let frac = Double(idx) / Double(segments)
        if frac > 0.85 { return Theme.accentSecondary }
        if frac > 0.65 { return Color(red: 1.0, green: 0.72, blue: 0.2) }
        return Theme.accent
    }
}
