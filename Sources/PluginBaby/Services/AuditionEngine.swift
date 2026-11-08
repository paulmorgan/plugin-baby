import Foundation
import AVFoundation
import AudioToolbox
import CoreAudioKit
import AppKit
import Observation

/// Hosts an Audio Unit for auditioning: effects process a sample in series,
/// instruments are driven by a test MIDI note. Can also open a plugin's own
/// editor window when it provides one.
@MainActor
@Observable
final class AuditionEngine {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var audioUnit: AVAudioUnit?
    private var file: AVAudioFile?
    private var editorWindow: NSWindow?

    var isPlaying = false
    var isBypassed = false
    var pluginLoaded = false
    var loadedKind: AUKind = .other
    var canOpenEditor = false
    var statusMessage = "Pick an Audio Unit and, for effects, an audio sample."

    private let testNote: UInt32 = 60   // middle C

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

    func loadPlugin(_ plugin: Plugin) {
        stop()
        closeEditor()
        guard let (description, kind) = AudioComponentDescriptionReader.description(for: plugin),
              kind != .other else {
            pluginLoaded = false
            loadedKind = .other
            canOpenEditor = false
            statusMessage = "\(plugin.name) isn’t an auditionable Audio Unit (effect or instrument)."
            return
        }
        statusMessage = "Loading \(plugin.name)…"
        AVAudioUnit.instantiate(with: description, options: []) { [weak self] unit, error in
            Task { @MainActor in
                guard let self else { return }
                if let unit {
                    self.attach(unit)
                    self.loadedKind = kind
                    self.pluginLoaded = true
                    self.canOpenEditor = unit.auAudioUnit.providesUserInterface
                    let label = kind == .instrument ? "instrument" : "effect"
                    self.statusMessage = "Loaded \(plugin.name) (\(label))."
                } else {
                    self.pluginLoaded = false
                    self.loadedKind = .other
                    self.canOpenEditor = false
                    self.statusMessage = "Failed to load \(plugin.name): \(error?.localizedDescription ?? "unknown error")."
                }
            }
        }
    }

    private func attach(_ unit: AVAudioUnit) {
        if let existing = audioUnit { engine.detach(existing) }
        audioUnit = unit
        engine.attach(unit)
    }

    /// Play: effects process the sample; instruments trigger a test note.
    func play() {
        if loadedKind == .instrument {
            playTestNote()
            return
        }
        guard let file else {
            statusMessage = "Choose an audio sample first."
            return
        }
        let format = file.processingFormat
        let mixer = engine.mainMixerNode
        if let unit = audioUnit {
            engine.connect(player, to: unit, format: format)
            engine.connect(unit, to: mixer, format: format)
            unit.auAudioUnit.shouldBypassEffect = isBypassed
        } else {
            engine.connect(player, to: mixer, format: format)
        }
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

    private func scheduleLoop(_ file: AVAudioFile) {
        player.scheduleFile(file, at: nil) { [weak self] in
            Task { @MainActor in
                guard let self, self.isPlaying else { return }
                self.scheduleLoop(file)
            }
        }
    }

    /// Send a single test MIDI note through a loaded instrument.
    func playTestNote() {
        guard let unit = audioUnit, loadedKind == .instrument else { return }
        engine.connect(unit, to: engine.mainMixerNode, format: nil)
        do {
            try engine.start()
        } catch {
            statusMessage = "Audio engine failed to start: \(error.localizedDescription)"
            return
        }
        MusicDeviceMIDIEvent(unit.audioUnit, 0x90, testNote, 100, 0)  // note on
        isPlaying = true
        statusMessage = "Playing test note (C4)…"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self, let unit = self.audioUnit else { return }
            MusicDeviceMIDIEvent(unit.audioUnit, 0x80, self.testNote, 0, 0)  // note off
            self.isPlaying = false
            self.statusMessage = "Test note finished."
        }
    }

    func stop() {
        if let unit = audioUnit, loadedKind == .instrument {
            MusicDeviceMIDIEvent(unit.audioUnit, 0x80, testNote, 0, 0)
        }
        player.stop()
        engine.stop()
        isPlaying = false
    }

    func setBypass(_ bypass: Bool) {
        isBypassed = bypass
        audioUnit?.auAudioUnit.shouldBypassEffect = bypass
    }

    // MARK: - Plugin editor window

    func openEditor() {
        guard let unit = audioUnit, unit.auAudioUnit.providesUserInterface else {
            statusMessage = "This plugin has no custom editor."
            return
        }
        unit.auAudioUnit.requestViewController { [weak self] controller in
            Task { @MainActor in
                guard let self else { return }
                guard let controller else {
                    self.statusMessage = "This plugin has no custom editor."
                    return
                }
                self.presentEditor(controller)
            }
        }
    }

    private func presentEditor(_ controller: NSViewController) {
        let window = NSWindow(contentViewController: controller)
        window.title = "Plugin Editor"
        window.styleMask = [.titled, .closable, .resizable]
        let size = controller.preferredContentSize
        window.setContentSize(size == .zero ? NSSize(width: 640, height: 420) : size)
        window.isReleasedWhenClosed = false
        window.center()
        editorWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func closeEditor() {
        editorWindow?.close()
        editorWindow = nil
    }
}
