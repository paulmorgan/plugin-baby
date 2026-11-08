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
    private var editorController: NSViewController?
    private var editorSizeObservation: NSKeyValueObservation?

    var isPlaying = false
    var isBypassed = false
    var pluginLoaded = false
    var loadedKind: AUKind = .other
    var canOpenEditor = false
    var statusMessage = "Pick an Audio Unit and, for effects, an audio sample."

    /// Name of the audio sample currently loaded (the bundled default unless the
    /// user picked their own).
    var sampleName = ""
    /// True while the loaded sample is the app's bundled default.
    var usingDefaultSample = false

    // Live visualization, published to the UI (updated on the main actor).
    var outputLevel: Float = 0
    var spectrum: [Float] = Array(repeating: 0, count: 28)

    private let testNote: UInt32 = 60   // middle C
    private let analyzer = SpectrumAnalyzer(fftSize: 1024, bandCount: 28)
    private var metering = false
    private var clapBackend: CLAPAuditionBackend?

    /// URL of the sample currently loaded (bundled default or user-chosen).
    private(set) var sampleURL: URL?

    init() {
        engine.attach(player)
        loadDefaultSample()
    }

    /// The audio sample shipped inside the app bundle, used unless the user
    /// chooses their own.
    static var defaultSampleURL: URL? {
        Bundle.main.url(forResource: "default-sample", withExtension: "mp3")
    }

    /// Load the bundled default sample (if present). Safe to call any time.
    func loadDefaultSample() {
        guard let url = Self.defaultSampleURL else {
            statusMessage = "No default sample is bundled with the app."
            return
        }
        do {
            file = try AVAudioFile(forReading: url)
            sampleName = url.lastPathComponent
            sampleURL = url
            usingDefaultSample = true
            statusMessage = "Using default sample."
        } catch {
            file = nil
            statusMessage = "Could not read the default sample: \(error.localizedDescription)"
        }
    }

    func loadSample(_ url: URL) {
        do {
            file = try AVAudioFile(forReading: url)
            sampleName = url.lastPathComponent
            sampleURL = url
            usingDefaultSample = false
            statusMessage = "Sample ready: \(url.lastPathComponent)"
        } catch {
            statusMessage = "Could not read sample: \(error.localizedDescription)"
        }
    }

    func loadPlugin(_ plugin: Plugin) {
        stop()
        closeEditor()
        clapBackend = nil

        if plugin.format == .clap {
            loadCLAP(plugin)
            return
        }

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

    /// Host a CLAP plugin through the dedicated CLAP backend (separate engine).
    private func loadCLAP(_ plugin: Plugin) {
        pluginLoaded = false
        canOpenEditor = false
        loadedKind = .other
        let sample = sampleURL ?? Self.defaultSampleURL
        guard let backend = CLAPAuditionBackend(plugin: plugin, sampleURL: sample) else {
            statusMessage = "Couldn\u{2019}t host \(plugin.name) as a CLAP plugin."
            return
        }
        backend.onMeter = { [weak self] level, bands in
            self?.outputLevel = level
            self?.spectrum = bands
        }
        clapBackend = backend
        loadedKind = backend.isInstrument ? .instrument : .effect
        pluginLoaded = true
        canOpenEditor = false   // CLAP editor UI is a later phase
        let label = backend.isInstrument ? "instrument" : "effect"
        statusMessage = "Loaded \(plugin.name) (CLAP \(label))."
    }

    private func attach(_ unit: AVAudioUnit) {
        if let existing = audioUnit { engine.detach(existing) }
        audioUnit = unit
        engine.attach(unit)
    }

    /// Play: effects process the sample; instruments trigger a test note.
    func play() {
        if let clap = clapBackend {
            if isPlaying { stop(); return }
            clap.play()
            isPlaying = true
            statusMessage = clap.isInstrument ? "Playing test note (C4)\u{2026}" : "Auditioning (CLAP)\u{2026}"
            if clap.isInstrument {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                    guard let self, self.isPlaying else { return }
                    self.stop()
                    self.statusMessage = "Test note finished."
                }
            }
            return
        }
        if loadedKind == .instrument {
            playTestNote()
            return
        }
        if file == nil { loadDefaultSample() }
        guard let file else {
            statusMessage = "No audio sample available. Choose one to preview effects."
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
        installMeterTap()
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
        installMeterTap()
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
        clapBackend?.stop()
        if let unit = audioUnit, loadedKind == .instrument {
            MusicDeviceMIDIEvent(unit.audioUnit, 0x80, testNote, 0, 0)
        }
        removeMeterTap()
        player.stop()
        engine.stop()
        isPlaying = false
    }

    // MARK: - Metering

    private func installMeterTap() {
        guard !metering else { return }
        let analyzer = self.analyzer
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            guard let channels = buffer.floatChannelData else { return }
            let frames = Int(buffer.frameLength)
            let (level, bands) = analyzer.process(channels[0], count: frames)
            Task { @MainActor in
                self?.outputLevel = level
                self?.spectrum = bands
            }
        }
        metering = true
    }

    private func removeMeterTap() {
        guard metering else { return }
        engine.mainMixerNode.removeTap(onBus: 0)
        metering = false
        outputLevel = 0
        spectrum = Array(repeating: 0, count: analyzer.bandCount)
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
        closeEditor()
        editorController = controller

        let window = NSWindow(contentViewController: controller)
        window.title = "Plugin Editor"
        window.styleMask = [.titled, .closable, .resizable]
        window.isReleasedWhenClosed = false
        applyEditorSize(to: window, from: controller)
        window.center()
        editorWindow = window

        // AU editors frequently report their true size asynchronously, after the
        // view has loaded its own layout. Keep the window fit to it as it settles.
        editorSizeObservation = controller.observe(\.preferredContentSize, options: [.new]) { [weak self, weak window] ctrl, _ in
            Task { @MainActor in
                guard let self, let window else { return }
                self.applyEditorSize(to: window, from: ctrl)
            }
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Size the editor window to the plugin view's real content, falling back to
    /// the view's own fitting size when the plugin hasn't reported one yet.
    private func applyEditorSize(to window: NSWindow, from controller: NSViewController) {
        var size = controller.preferredContentSize
        if size.width < 1 || size.height < 1 {
            controller.view.layoutSubtreeIfNeeded()
            size = controller.view.fittingSize
        }
        guard size.width >= 1, size.height >= 1 else { return }
        window.setContentSize(size)
        // Most AU plugin UIs are drawn at a fixed design size; stop the window
        // from collapsing smaller than the view and clipping controls.
        window.contentMinSize = size
    }

    private func closeEditor() {
        editorSizeObservation?.invalidate()
        editorSizeObservation = nil
        editorWindow?.close()
        editorWindow = nil
        editorController = nil
    }
}
