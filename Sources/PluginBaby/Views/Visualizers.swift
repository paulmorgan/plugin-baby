import SwiftUI

/// Neon spectrum bars driven by the audition engine. When nothing is playing the
/// values are zero, so it rests as a quiet baseline.
///
/// Rendering note: this view updates many times per second while audio plays, so
/// it deliberately uses plain SwiftUI shapes and **no GPU shadow/blur filters**.
/// An animated `Canvas` with per-bar `.shadow` filters hangs the renderer on some
/// older discrete GPUs (e.g. AMD Radeon on 2015–2018 Intel Macs); plain fills are
/// cheap and render reliably everywhere. Static neon glows elsewhere are fine.
struct SpectrumView: View {
    var bands: [Float]
    var active: Bool

    var body: some View {
        GeometryReader { geo in
            let n = max(bands.count, 1)
            let gap: CGFloat = 2
            let barW = max(1, (geo.size.width - gap * CGFloat(n - 1)) / CGFloat(n))

            HStack(alignment: .bottom, spacing: gap) {
                ForEach(Array(bands.enumerated()), id: \.offset) { i, raw in
                    let v = CGFloat(max(0.02, min(1, raw)))
                    RoundedRectangle(cornerRadius: barW * 0.35)
                        .fill(barColor(index: i, count: n).opacity(active ? 0.95 : 0.35))
                        .frame(width: barW, height: max(2, v * geo.size.height))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .animation(.linear(duration: 0.08), value: bands)
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.background.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.hairline)
        )
    }

    /// Color shifts cyan→magenta across the spectrum.
    private func barColor(index i: Int, count n: Int) -> Color {
        let t = Double(i) / Double(max(1, n - 1))
        return Color(red: 0.0 + t, green: 0.80 - 0.62 * t, blue: 1.0 - 0.38 * t)
    }
}

/// A single vertical neon level meter (peak, 0…1). Plain fills only — no
/// per-segment shadow filter, for the same renderer-safety reason as above.
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
                }
            }
        }
        .animation(.linear(duration: 0.08), value: level)
    }

    private func segColor(_ idx: Int) -> Color {
        let frac = Double(idx) / Double(segments)
        if frac > 0.85 { return Theme.accentSecondary }
        if frac > 0.65 { return Color(red: 1.0, green: 0.72, blue: 0.2) }
        return Theme.accent
    }
}
