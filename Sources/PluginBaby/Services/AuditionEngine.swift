import Foundation
import AVFoundation
import Observation

/// Plays an audio sample through a loaded Audio Unit effect using AVAudioEngine.
@MainActor
@Observable
final class AuditionEngine {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var audioUnit: AVAudioUnit?
    private var file: AVAudioFile?

    var isPlaying = false
    var isBypassed = false
    var pluginLoaded = false
    var statusMessage = "Pick an Audio Unit effect and an audio sample."

    init() {
        engine.attach(player)
    }

    func loadSample(_ url: URL) {
        do {
            file = try AVAudioFile(forReading: url)
            statusMessage = "Sample ready: \(url.lastPathComponent)"
        } catch {
            file = nil
            statusMessage = "Could not read sample: \(error.localizedDescription)"
        }
    }

    func loadEffect(for plugin: Plugin) {
        guard let description = AudioComponentDescriptionReader.effectDescription(for: plugin) else {
            pluginLoaded = false
            statusMessage = "\(plugin.name) isn’t an Audio Unit effect, so it can’t process a sample yet."
            return
        }
        statusMessage = "Loading \(plugin.name)…"
        AVAudioUnit.instantiate(with: description, options: []) { [weak self] unit, error in
            Task { @MainActor in
                guard let self else { return }
                if let unit {
                    self.attach(unit)
                    self.pluginLoaded = true
                    self.statusMessage = "Loaded \(plugin.name)."
                } else {
                    self.pluginLoaded = false
                    self.statusMessage = "Failed to load \(plugin.name): \(error?.localizedDescription ?? "unknown error")."
                }
            }
        }
    }

    private func attach(_ unit: AVAudioUnit) {
        if let existing = audioUnit {
            engine.detach(existing)
        }
        audioUnit = unit
        engine.attach(unit)
    }

    func play() {
        guard let file else {
            statusMessage = "Choose an audio sample first."
            return
        }
        let format = file.processingFormat
        connectGraph(format: format)
        do {
            try engine.start()
        } catch {
            statusMessage = "Audio engine failed to start: \(error.localizedDescription)"
            return
        }
        player.stop()
        isPlaying = true
        scheduleLoop(file)
        player.play()
    }

    private func connectGraph(format: AVAudioFormat) {
        let mixer = engine.mainMixerNode
        if let unit = audioUnit {
            engine.connect(player, to: unit, format: format)
            engine.connect(unit, to: mixer, format: format)
            unit.auAudioUnit.shouldBypassEffect = isBypassed
        } else {
            engine.connect(player, to: mixer, format: format)
        }
    }

    private func scheduleLoop(_ file: AVAudioFile) {
        player.scheduleFile(file, at: nil) { [weak self] in
            Task { @MainActor in
                guard let self, self.isPlaying else { return }
                self.scheduleLoop(file)
            }
        }
    }

    func stop() {
        player.stop()
        engine.stop()
        isPlaying = false
    }

    func setBypass(_ bypass: Bool) {
        isBypassed = bypass
        audioUnit?.auAudioUnit.shouldBypassEffect = bypass
    }
}
