import Foundation
import AVFoundation
import AudioToolbox
import CoreAudioKit
import AppKit
import SwiftUI
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

    /// Adjustable parameters of the loaded CLAP plugin (empty for AUs or a CLAP
    /// with no parameters). The UI draws a slider per entry.
    var clapParameters: [CLAPHost.Param] = []
    /// Live value of each CLAP parameter, keyed by id — the slider bindings.
    var clapParamValues: [UInt32: Double] = [:]

    private let testNote: UInt32 = 60   // middle C
    private let analyzer = SpectrumAnalyzer(fftSize: 1024, bandCount: 28)
    private var metering = false
    private var clapBackend: CLAPAuditionBackend?
    /// Identity of the plugin currently instantiated, so the editor and Preview
    /// can share one instance (edits persist) and editing needs no prior Preview.
    private var loadedPluginKey: String?

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
        // Already instantiated this exact AU (e.g. its editor is open)? Keep the
        // same instance so edits persist and the editor stays wired to the audio.
        if plugin.format == .audioUnit, audioUnit != nil, loadedPluginKey == plugin.identityKey {
            return
        }
        stop()
        closeEditor()
        clapBackend = nil
        clapParameters = []
        clapParamValues = [:]
        loadedPluginKey = nil

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
                    self.loadedPluginKey = plugin.identityKey
                    // Any loaded AU can attempt to open its editor; whether one
                    // actually appears is decided when we request the view
                    // controller (providesUserInterface is unreliable).
                    self.canOpenEditor = true
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

        // Read the plugin's parameters so the UI can offer live sliders.
        clapParameters = backend.parameters()
        clapParamValues = Dictionary(uniqueKeysWithValues:
            clapParameters.map { ($0.id, backend.parameterValue(id: $0.id)) })

        let label = backend.isInstrument ? "instrument" : "effect"
        let paramNote = clapParameters.isEmpty ? "" : " · \(clapParameters.count) parameter\(clapParameters.count == 1 ? "" : "s")"
        statusMessage = "Loaded \(plugin.name) (CLAP \(label))\(paramNote)."
    }

    /// Adjust a CLAP parameter live (effective on the next audio block).
    func setClapParameter(id: UInt32, value: Double) {
        clapParamValues[id] = value
        clapBackend?.setParameter(id: id, value: value)
    }

    /// Reset every CLAP parameter to its default value.
    func resetClapParameters() {
        for p in clapParameters { setClapParameter(id: p.id, value: p.defaultValue) }
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

    /// Open the editor for a specific plugin, loading it first if it isn't the
    /// one already instantiated. Lets the user reach an AU's controls without
    /// having to press Preview first.
    func openEditor(for plugin: Plugin) {
        guard plugin.format == .audioUnit else {
            statusMessage = "CLAP controls appear as inline sliders; Audio Units use their own editor."
            return
        }
        if audioUnit != nil, loadedPluginKey == plugin.identityKey {
            openEditor()
            return
        }
        guard let (description, kind) = AudioComponentDescriptionReader.description(for: plugin),
              kind != .other else {
            statusMessage = "\(plugin.name) can’t be hosted for editing."
            return
        }
        statusMessage = "Opening \(plugin.name)…"
        AVAudioUnit.instantiate(with: description, options: []) { [weak self] unit, error in
            Task { @MainActor in
                guard let self else { return }
                guard let unit else {
                    self.statusMessage = "Couldn’t load \(plugin.name): \(error?.localizedDescription ?? "unknown error")."
                    return
                }
                self.attach(unit)
                self.loadedKind = kind
                self.pluginLoaded = true
                self.loadedPluginKey = plugin.identityKey
                self.canOpenEditor = true
                self.openEditor()
            }
        }
    }

    func openEditor() {
        guard let unit = audioUnit else {
            statusMessage = "Load a plugin first, then open its editor."
            return
        }
        // An editor window already exists (possibly closed but retained)? Just
        // resurface it. Re-requesting a view controller can return nil the second
        // time — an AU vends its UI once — which would wrongly fall back to the
        // generic editor.
        if let window = editorWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        unit.auAudioUnit.requestViewController { [weak self] controller in
            Task { @MainActor in
                guard let self else { return }
                if let controller {
                    self.presentEditor(controller)          // the plugin's own UI
                } else {
                    self.presentGenericEditor(for: unit)    // app-built parameter sliders
                }
            }
        }
    }

    /// Fallback editor built from the AU's own parameter tree, for plugins that
    /// provide no view controller we can host. Guarantees "Open editor" always
    /// shows adjustable controls.
    private func presentGenericEditor(for unit: AVAudioUnit) {
        let params = unit.auAudioUnit.parameterTree?.allParameters ?? []
        let name = unit.auAudioUnit.audioUnitName ?? "Plugin"
        let view = AUParameterEditorView(title: name, parameters: params)
        let controller = NSHostingController(rootView: view)
        controller.preferredContentSize = NSSize(width: 380, height: params.isEmpty ? 160 : 440)
        presentEditor(controller)
        statusMessage = params.isEmpty
            ? "\(name) has no adjustable parameters."
            : "Editing \(params.count) parameter\(params.count == 1 ? "" : "s") (generic editor)."
    }

    private func presentEditor(_ controller: NSViewController) {
        closeEditor()
        editorController = controller

        let window = NSWindow(contentViewController: controller)
        window.title = "Plugin Editor"
        window.styleMask = [.titled, .closable, .resizable]
        window.isReleasedWhenClosed = false
        // Float above the main window so the editor stays in front while you
        // audition, instead of slipping behind it.
        window.level = .floating
        window.hidesOnDeactivate = false
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
