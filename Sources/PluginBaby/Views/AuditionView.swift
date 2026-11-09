import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The Audition screen: pick a plugin, choose a sample, and play it through the audio engine with live visualizers.
struct AuditionView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedPluginID: Plugin.ID?
    @State private var sampleName = "No sample selected"

    private var auPlugins: [Plugin] {
        model.plugins.filter { $0.format == .audioUnit }
    }

    var body: some View {
        @Bindable var audition = model.audition
        let isInstrument = audition.loadedKind == .instrument

        VStack(alignment: .leading, spacing: 18) {
            Text("Audition").font(.largeTitle).bold()
            Text("Play a sample through an Audio Unit **effect**, or trigger a test note on an Audio Unit **instrument**. VST3/CLAP hosting comes later.")
                .foregroundStyle(.secondary)

            Picker("Plugin", selection: $selectedPluginID) {
                Text("Choose an Audio Unit…").tag(Plugin.ID?.none)
                ForEach(auPlugins) { plugin in
                    Text("\(plugin.name) — \(plugin.manufacturer)")
                        .tag(Plugin.ID?.some(plugin.id))
                }
            }
            .onChange(of: selectedPluginID) { _, newValue in
                if let id = newValue,
                   let plugin = model.plugins.first(where: { $0.id == id }) {
                    model.audition.loadPlugin(plugin)
                }
            }

            // Sample picker only matters for effects.
            if !isInstrument {
                HStack {
                    Button { pickSample() } label: {
                        Label("Choose sample…", systemImage: "waveform")
                    }
                    Text(sampleName).foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 16) {
                Button {
                    audition.isPlaying ? model.audition.stop() : model.audition.play()
                } label: {
                    Label(
                        audition.isPlaying ? "Stop" : (isInstrument ? "Play test note" : "Play"),
                        systemImage: audition.isPlaying ? "stop.fill" : "play.fill"
                    )
                    .frame(width: 130)
                }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(!audition.pluginLoaded)

                if !isInstrument {
                    Toggle("Bypass (A/B)", isOn: Binding(
                        get: { audition.isBypassed },
                        set: { model.audition.setBypass($0) }
                    ))
                    .toggleStyle(.switch)
                    .disabled(!audition.pluginLoaded)
                }

                Button {
                    if let id = selectedPluginID,
                       let plugin = model.plugins.first(where: { $0.id == id }) {
                        model.audition.openEditor(for: plugin)
                    }
                } label: {
                    Label("Open editor", systemImage: "slider.horizontal.3")
                }
                .disabled(selectedPluginID == nil)
            }

            Text(audition.statusMessage)
                .font(.callout)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .navigationTitle("Audition")
    }

    private func pickSample() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            model.audition.loadSample(url)
            sampleName = url.lastPathComponent
        }
    }
}
