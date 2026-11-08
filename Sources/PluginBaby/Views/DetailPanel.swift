import SwiftUI
import AppKit

/// Right-hand dashboard panel: the selected plugin, a Manage menu, a live
/// preview, and the spectrum + level meters.
struct DetailPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let plugin = model.selectedPlugin {
                content(for: plugin)
            } else {
                placeholder
            }
            Spacer()
            visualizer
        }
        .padding(14)
        .frame(width: 260)
        .background(Theme.backgroundRaised)
        .overlay(Rectangle().frame(width: 1).foregroundStyle(Theme.hairline), alignment: .leading)
    }

    // MARK: Selected plugin

    @ViewBuilder private func content(for plugin: Plugin) -> some View {
        let kind = auKindLabel(plugin)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(plugin.name)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                Spacer()
                FormatBadge(format: plugin.format)
            }

            infoRow("Type", kind)
            infoRow("Maker", plugin.manufacturer)
            infoRow("Version", plugin.version)
            infoRow("Where", plugin.domain.rawValue)
            infoRow("Arch", plugin.architecture.rawValue)

            statusBlock(for: plugin)

            HStack(spacing: 8) {
                Button {
                    preview(plugin)
                } label: {
                    Label(model.audition.isPlaying ? "Stop" : "Preview",
                          systemImage: model.audition.isPlaying ? "stop.fill" : "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(plugin.format != .audioUnit)

                Menu {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([plugin.path])
                    }
                    if plugin.format == .audioUnit {
                        Button("Validate (auval)") { model.validate(plugin) }
                    }
                    Divider()
                    Button(plugin.domain.needsPrivilege ? "Archive (needs admin)…" : "Archive",
                           role: .destructive) {
                        model.archivePlugin(plugin)
                    }
                } label: {
                    Label("Manage", systemImage: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
        }
    }

    @ViewBuilder private func statusBlock(for plugin: Plugin) -> some View {
        let v = model.validationStatus(for: plugin)
        let health = model.health(for: plugin)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: v.symbol).foregroundStyle(v.color)
                Text(v.label).font(.system(size: 11, weight: .semibold)).foregroundStyle(v.color)
            }
            if let detail = health.detail {
                HStack(spacing: 6) {
                    Image(systemName: health.symbol).foregroundStyle(health.color)
                    Text(detail.capitalized).font(.system(size: 10)).foregroundStyle(health.color)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.background.opacity(0.5)))
    }

    private var placeholder: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No plugin selected")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Pick a plugin from the grid to see details and preview it.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: Visualizer

    private var visualizer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("OUTPUT")
                .font(.system(size: 9, weight: .bold)).tracking(1.5)
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: 8) {
                SpectrumView(bands: model.audition.spectrum, active: model.audition.isPlaying)
                    .frame(height: 90)
                HStack(spacing: 4) {
                    LevelMeterView(level: model.audition.outputLevel, active: model.audition.isPlaying)
                    LevelMeterView(level: model.audition.outputLevel, active: model.audition.isPlaying)
                }
                .frame(width: 18, height: 90)
            }
            Text(model.audition.statusMessage)
                .font(.system(size: 9))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
        }
    }

    // MARK: Actions

    private func preview(_ plugin: Plugin) {
        if model.audition.isPlaying { model.audition.stop(); return }
        model.audition.loadPlugin(plugin)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            model.audition.play()
        }
    }

    private func auKindLabel(_ plugin: Plugin) -> String {
        guard plugin.format == .audioUnit,
              let (_, kind) = AudioComponentDescriptionReader.description(for: plugin) else {
            return plugin.format.rawValue
        }
        switch kind {
        case .effect: return "Effect"
        case .instrument: return "Instrument"
        case .other: return "Audio Unit"
        }
    }
}
