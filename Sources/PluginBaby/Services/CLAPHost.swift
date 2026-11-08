import Foundation

/// Thin Swift wrapper over the C CLAP host shim (`clap_shim.h`). All the ABI /
/// vtable work lives in the C side; this just presents it to Swift safely.
final class CLAPHost {
    struct Descriptor {
        let id: String
        let name: String
        let vendor: String
        let version: String
        let isInstrument: Bool
    }

    /// Discover the plugins inside a `.clap` without keeping them loaded.
    static func scan(path: String) -> [Descriptor] {
        var buf = [pb_clap_descriptor](repeating: pb_clap_descriptor(), count: 32)
        let count = pb_clap_scan(path, &buf, Int32(buf.count))
        guard count > 0 else { return [] }
        let n = min(Int(count), buf.count)
        return (0..<n).map { i in
            var d = buf[i]
            return Descriptor(
                id: Self.string(&d.id),
                name: Self.string(&d.name),
                vendor: Self.string(&d.vendor),
                version: Self.string(&d.version),
                isInstrument: d.is_instrument)
        }
    }

    private var handle: OpaquePointer?
    let inputChannels: Int
    let outputChannels: Int
    let isInstrument: Bool

    /// Open a specific plugin id and activate it for the given format.
    init?(path: String, pluginID: String, sampleRate: Double, maxFrames: UInt32) {
        guard let h = pb_clap_open(path, pluginID, sampleRate, maxFrames) else { return nil }
        handle = h
        inputChannels  = Int(pb_clap_input_channels(h))
        outputChannels = Int(pb_clap_output_channels(h))
        isInstrument   = pb_clap_is_instrument(h)
    }

    /// Audio-thread: run one block through the plugin. Pass `nil` input for
    /// instruments. Pointers are planar: `in[ch]` / `out[ch]`.
    @discardableResult
    func process(input: UnsafePointer<UnsafePointer<Float>?>?, inputChannels inCh: Int,
                 output: UnsafePointer<UnsafeMutablePointer<Float>?>?, outputChannels outCh: Int,
                 frames: Int, steadyTime: Int64) -> Bool {
        guard let h = handle else { return false }
        return pb_clap_process(h, input, UInt32(inCh), output, UInt32(outCh),
                               UInt32(frames), steadyTime)
    }

    func noteOn(key: Int, velocity: Double) {
        guard let h = handle else { return }
        pb_clap_note_on(h, Int16(key), velocity)
    }
    func noteOff(key: Int) {
        guard let h = handle else { return }
        pb_clap_note_off(h, Int16(key))
    }
    func allNotesOff() {
        guard let h = handle else { return }
        pb_clap_all_notes_off(h)
    }

    func close() {
        if let h = handle { pb_clap_close(h); handle = nil }
    }
    deinit { close() }

    // Fixed-size C char arrays import as homogeneous tuples; read as a C string.
    private static func string<T>(_ tuple: inout T) -> String {
        withUnsafePointer(to: &tuple) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: MemoryLayout<T>.size) {
                String(cString: $0)
            }
        }
    }
}
