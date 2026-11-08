import SwiftUI

/// A format badge chip (AU / VST3 / …), colored per format.
struct FormatBadge: View {
    var format: PluginFormat
    var body: some View {
        Text(format == .audioUnit ? "AU" : format.rawValue)
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(
                Capsule().fill(Theme.color(for: format).opacity(0.18))
            )
            .overlay(Capsule().strokeBorder(Theme.color(for: format).opacity(0.6)))
            .foregroundStyle(Theme.color(for: format))
    }
}

/// A small generated glyph standing in for the plugin's "thumbnail".
struct PluginGlyph: View {
    var format: PluginFormat
    var seed: Int
    var body: some View {
        let color = Theme.color(for: format)
        RoundedRectangle(cornerRadius: 8)
            .fill(Theme.background)
            .overlay(
                Canvas { ctx, rect in
                    // A little deterministic "waveform" per plugin.
                    var path = Path()
                    let mid = rect.height / 2
                    let n = 14
                    for i in 0...n {
                        let x = rect.width * CGFloat(i) / CGFloat(n)
                        let phase = Double((seed + i * 37) % 97) / 97.0
                        let amp = (0.2 + 0.7 * sin(phase * .pi)) * Double(rect.height) * 0.4
                        let y = mid + CGFloat((i % 2 == 0 ? 1 : -1)) * CGFloat(amp)
                        if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    ctx.addFilter(.shadow(color: color.opacity(0.7), radius: 3))
                    ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                }
                .padding(6)
            )
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(color.opacity(0.35)))
    }
}

/// One plugin in the dashboard grid.
struct PluginCard: View {
    @Environment(AppModel.self) private var model
    var plugin: Plugin
    var selected: Bool
    var onSelect: () -> Void

    private var validation: ValidationStatus { model.validationStatus(for: plugin) }
    private var health: PluginHealth { model.health(for: plugin) }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                PluginGlyph(format: plugin.format, seed: plugin.identityKey.hashValue)
                    .frame(width: 52, height: 40)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(plugin.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        FormatBadge(format: plugin.format)
                    }
                    Text(plugin.manufacturer)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        Label(plugin.domain.rawValue, systemImage: plugin.domain == .system ? "lock.shield" : "person")
                            .labelStyle(.titleAndIcon)
                        Text("v\(plugin.version)")
                    }
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.textSecondary.opacity(0.9))
                }

                Spacer(minLength: 4)

                statusIcon
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .neonPanel(selected: selected)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var statusIcon: some View {
        if validation == .failed {
            Image(systemName: "xmark.octagon.fill").foregroundStyle(Theme.accentSecondary)
        } else if validation == .running {
            ProgressView().controlSize(.small)
        } else if validation == .passed {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(Color(red: 0.3, green: 0.9, blue: 0.55))
        } else if !health.isOK {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(health.color)
        } else {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(Theme.textSecondary.opacity(0.5))
        }
    }
}
