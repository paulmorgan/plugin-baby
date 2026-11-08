import Foundation
import AVFoundation
import AudioToolbox

// End-to-end verification of Plugin Baby's service layer. Reuses the app's own
// source files (Models + Services). Uses a throwaway test plugin for the
// destructive archive/restore checks; never touches real installed plugins.

var failures = 0
func check(_ label: String, _ condition: Bool, _ detail: String = "") {
    let mark = condition ? "✅" : "❌"
    if !condition { failures += 1 }
    print("\(mark) \(label)\(detail.isEmpty ? "" : "  —  \(detail)")")
}

// MARK: - 1. Read-only scan of the real catalog

let realPlugins = PluginScanner.scanAll()
print("\n== Catalog scan ==")
print("Found \(realPlugins.count) installed plugins in ~/Library/Audio/Plug-Ins")
let byFormat = Dictionary(grouping: realPlugins, by: { $0.format.rawValue })
    .mapValues(\.count).sorted { $0.key < $1.key }
for (format, count) in byFormat { print("  \(format): \(count)") }

// MARK: - 2. Archive → restore round-trip on a throwaway plugin

print("\n== Archive / restore round-trip (test plugin) ==")
print("Storage location: \(Persistence.shared.locationDescription)")
let fm = FileManager.default
let componentsDir = PluginScanner.userPluginRoot().appendingPathComponent("Components", isDirectory: true)
try? fm.createDirectory(at: componentsDir, withIntermediateDirectories: true)
let testBundle = componentsDir.appendingPathComponent("PluginBabyTest.component", isDirectory: true)

// Build a minimal, valid .component bundle with a real Mach-O executable.
func makeTestBundle() throws {
    try? fm.removeItem(at: testBundle)
    let macOS = testBundle.appendingPathComponent("Contents/MacOS", isDirectory: true)
    try fm.createDirectory(at: macOS, withIntermediateDirectories: true)
    // Reuse a tiny system Mach-O so lipo/codesign have something real to read.
    try fm.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"),
                    to: macOS.appendingPathComponent("PluginBabyTest"))
    let info: [String: Any] = [
        "CFBundleName": "PluginBabyTest",
        "CFBundleIdentifier": "com.pluginbabytest.demo",
        "CFBundleExecutable": "PluginBabyTest",
        "CFBundleShortVersionString": "9.9",
        "AudioComponents": [[
            "type": "aufx", "subtype": "tst1", "manufacturer": "PBby",
            "name": "PluginBabyTest", "description": "test",
            "factoryFunction": "x", "version": 1
        ]]
    ]
    let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
    try data.write(to: testBundle.appendingPathComponent("Contents/Info.plist"))
}

do {
    try makeTestBundle()
    let afterCreate = PluginScanner.scanAll()
    let found = afterCreate.first { $0.name == "PluginBabyTest" && $0.format == .audioUnit }
    check("Scan finds the test plugin", found != nil,
          found.map { "\($0.manufacturer) / \($0.version) / \($0.architecture.rawValue)" } ?? "not found")

    guard let plugin = found else { throw PBError.unsafe("test plugin not scanned") }

    let archiver = ArchiveManager()
    let entry = try archiver.archive(plugin)
    check("Archive moves bundle out of install dir", !fm.fileExists(atPath: testBundle.path))
    check("Archive copy exists in archive dir", fm.fileExists(atPath: entry.archivedPath.path))
    check("Scan no longer lists archived plugin",
          !PluginScanner.scanAll().contains { $0.name == "PluginBabyTest" })

    try archiver.restore(entry)
    check("Restore returns bundle to original location", fm.fileExists(atPath: testBundle.path))
    check("Restore removes the archive copy", !fm.fileExists(atPath: entry.archivedPath.path))
    check("Scan finds the restored plugin",
          PluginScanner.scanAll().contains { $0.name == "PluginBabyTest" })

    // Cleanup
    try? fm.removeItem(at: testBundle)
    check("Cleanup removed the test plugin", !fm.fileExists(atPath: testBundle.path))
} catch {
    check("Archive/restore round-trip", false, error.localizedDescription)
    try? fm.removeItem(at: testBundle)
}

// MARK: - 3. Audition signal path (offline render through a system Audio Unit)

print("\n== Audition signal path (offline render) ==")
func verifyAudition() -> (ok: Bool, detail: String) {
    // Apple's built-in delay effect: type 'aufx', subtype 'dely', manufacturer 'appl'.
    var desc = AudioComponentDescription(
        componentType: kAudioUnitType_Effect,
        componentSubType: kAudioUnitSubType_Delay,
        componentManufacturer: kAudioUnitManufacturer_Apple,
        componentFlags: 0, componentFlagsMask: 0)

    var unit: AVAudioUnit?
    let sem = DispatchSemaphore(value: 0)
    AVAudioUnit.instantiate(with: desc, options: []) { u, _ in unit = u; sem.signal() }
    _ = sem.wait(timeout: .now() + 10)
    guard let effect = unit else { return (false, "could not instantiate Apple delay AU") }

    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    engine.attach(player)
    engine.attach(effect)
    guard let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2) else {
        return (false, "format")
    }
    engine.connect(player, to: effect, format: format)
    engine.connect(effect, to: engine.mainMixerNode, format: format)

    // Fill a buffer with noise to push through the graph.
    let frames: AVAudioFrameCount = 4096
    guard let noise = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
        return (false, "buffer")
    }
    noise.frameLength = frames
    for ch in 0..<Int(format.channelCount) {
        if let p = noise.floatChannelData?[ch] {
            for i in 0..<Int(frames) { p[i] = Float.random(in: -0.5...0.5) }
        }
    }

    do {
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: frames)
        try engine.start()
        player.scheduleBuffer(noise, at: nil, options: [], completionHandler: nil)
        player.play()
        guard let out = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: frames) else {
            return (false, "out buffer")
        }
        let status = try engine.renderOffline(frames, to: out)
        engine.stop()
        guard status == .success else { return (false, "render status \(status.rawValue)") }
        // Confirm the output isn't silent — audio actually flowed through the effect.
        var peak: Float = 0
        for ch in 0..<Int(out.format.channelCount) {
            if let p = out.floatChannelData?[ch] {
                for i in 0..<Int(out.frameLength) { peak = max(peak, abs(p[i])) }
            }
        }
        return (peak > 1e-5, String(format: "output peak = %.4f", peak))
    } catch {
        return (false, error.localizedDescription)
    }
}

let audition = verifyAudition()
check("Offline render through an Audio Unit produces audio", audition.ok, audition.detail)

// Also exercise the app's real description reader on an installed AU effect, if any.
if let auEffect = realPlugins.first(where: { plugin in
    plugin.format == .audioUnit && AudioComponentDescriptionReader.effectDescription(for: plugin) != nil
}) {
    check("Reader builds a description from a real installed AU effect", true, auEffect.name)
} else {
    print("ℹ️  No installed AU effect found to exercise the description reader (skipped).")
}

print("\n== Result ==")
if failures == 0 {
    print("ALL CHECKS PASSED")
    exit(0)
} else {
    print("\(failures) CHECK(S) FAILED")
    exit(1)
}
