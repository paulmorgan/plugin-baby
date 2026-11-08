import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct AuditionView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedPluginID: Plugin.ID?
    @State private var sampleName = "No sample selected"

    private var auPlugins: [Plugin] {
        model.plugins.filter { $0.format == .audioUnit }
    }

    var body: some View {
        @Bindable var audition = model.audition

        VStack(alignment: .leading, spacing: 18) {
            Text("Audition").font(.largeTitle).bold()
            Text("Play an audio sample through an Audio Unit effect. VST3/CLAP hosting comes in a later phase.")
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
                    model.audition.loadEffect(for: plugin)
                }
            }

            HStack {
                Button {
                    pickSample()
                } label: {
                    Label("Choose sample…", systemImage: "waveform")
                }
                Text(sampleName).foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                Button {
                    audition.isPlaying ? model.audition.stop() : model.audition.play()
                } label: {
                    Label(audition.isPlaying ? "Stop" : "Play",
                          systemImage: audition.isPlaying ? "stop.fill" : "play.fill")
                        .frame(width: 90)
                }
                .keyboardShortcut(.space, modifiers: [])

                Toggle("Bypass (A/B)", isOn: Binding(
                    get: { audition.isBypassed },
                    set: { model.audition.setBypass($0) }
                ))
                .toggleStyle(.switch)
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
