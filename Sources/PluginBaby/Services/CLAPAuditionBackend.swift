import Foundation
import AVFoundation
import Observation

/// Hosts a CLAP plugin for auditioning. CLAP plugins are not `AVAudioUnit`s, so
/// we render them ourselves: an `AVAudioSourceNode` pulls sample frames (for
/// effects) or triggers a note (for instruments), runs the block through the
/// plugin via the C shim, and feeds the result into `AVAudioEngine`. The mixer
/// is tapped for the same spectrum/level meters the AU path uses.
///
/// Status: compiles and is wired end-to-end; not yet exercised against a real
/// `.clap` (none installed on the dev machine). See docs/CLAP-AUDITION.md.
@MainActor
final class CLAPAuditionBackend {
    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private let host: CLAPHost
    private let core: CLAPRenderCore
    private let analyzer = SpectrumAnalyzer(fftSize: 1024, bandCount: 28)
    private var metering = false

    let isInstrument: Bool
    let descriptorName: String

    /// Called on the main actor with (level, bands) while playing.
    var onMeter: ((Float, [Float]) -> Void)?

    private let maxFrames = 4096
    private let testNote = 60   // middle C

    /// Build a backend for a CLAP plugin. Picks an effect descriptor if present,
    /// else the first plugin in the bundle. Returns nil if it can't be hosted.
    init?(plugin: Plugin, sampleURL: URL?) {
        let descriptors = CLAPHost.scan(path: plugin.path.path)
        guard let desc = descriptors.first(where: { !$0.isInstrument }) ?? descriptors.first else {
            return nil
        }

        // Use the engine's hardware output format as the common rate/layout.
        let outFormat = engine.outputNode.outputFormat(forBus: 0)
        let sampleRate = outFormat.sampleRate > 0 ? outFormat.sampleRate : 48_000

        guard let host = CLAPHost(path: plugin.path.path, pluginID: desc.id,
                                  sampleRate: sampleRate, maxFrames: UInt32(maxFrames)) else {
            return nil
        }
        self.host = host
        self.isInstrument = host.isInstrument
        self.descriptorName = desc.name

        let outCh = max(host.outputChannels, 1)
        let inCh  = host.isInstrument ? 0 : max(host.inputChannels, 1)

        // Decode the sample to planar float at the engine rate / input channels.
        var sample: [[Float]] = []
        if !host.isInstrument, let url = sampleURL {
            sample = Self.decode(url: url, sampleRate: sampleRate, channels: inCh) ?? []
        }

        self.core = CLAPRenderCore(host: host,
                                   inputChannels: inCh,
                                   outputChannels: outCh,
                                   maxFrames: maxFrames,
                                   sample: sample)

        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: sampleRate,
                                         channels: AVAudioChannelCount(outCh),
                                         interleaved: false) else { return nil }

        let renderCore = core
        let node = AVAudioSourceNode(format: format) { _, _, frameCount, abl in
            renderCore.render(frameCount: Int(frameCount), abl: abl)
            return noErr
        }
        sourceNode = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
    }

    // MARK: - Parameters

    /// The plugin's adjustable parameters (empty if it exposes none).
    func parameters() -> [CLAPHost.Param] { host.parameters() }

    /// Current value of a parameter.
    func parameterValue(id: UInt32) -> Double { host.parameterValue(id: id) }

    /// Adjust a parameter live; takes effect on the next audio block.
    func setParameter(id: UInt32, value: Double) { host.setParameter(id: id, value: value) }

    func play() {
        installMeterTap()
        core.reset()
        do {
            try engine.start()
        } catch {
            return
        }
        if isInstrument {
            host.noteOn(key: testNote, velocity: 0.9)
        }
    }

    func stop() {
        if isInstrument { host.allNotesOff() }
        removeMeterTap()
        engine.stop()
    }

    // MARK: - Metering (mirrors AuditionEngine)

    private func installMeterTap() {
        guard !metering else { return }
        let analyzer = self.analyzer
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            guard let channels = buffer.floatChannelData else { return }
            let frames = Int(buffer.frameLength)
            let (level, bands) = analyzer.process(channels[0], count: frames)
            Task { @MainActor in
                self?.onMeter?(level, bands)
            }
        }
        metering = true
    }

    private func removeMeterTap() {
        guard metering else { return }
        engine.mainMixerNode.removeTap(onBus: 0)
        metering = false
        onMeter?(0, Array(repeating: 0, count: analyzer.bandCount))
    }

    // MARK: - Sample decode

    /// Decode an audio file to planar float at the target rate and channel count.
    nonisolated static func decode(url: URL, sampleRate: Double, channels: Int) -> [[Float]]? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let inFormat = file.processingFormat
        guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: sampleRate,
                                         channels: AVAudioChannelCount(channels),
                                         interleaved: false),
              let converter = AVAudioConverter(from: inFormat, to: target) else { return nil }

        // Read the whole file into a buffer at its native format.
        let inFrames = AVAudioFrameCount(file.length)
        guard inFrames > 0,
              let inBuf = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: inFrames),
              (try? file.read(into: inBuf)) != nil else { return nil }

        let outCapacity = AVAudioFrameCount(Double(inFrames) * sampleRate / inFormat.sampleRate) + 4096
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: outCapacity) else { return nil }

        var fed = false
        var error: NSError?
        let status = converter.convert(to: outBuf, error: &error) { _, outStatus in
            if fed { outStatus.pointee = .endOfStream; return nil }
            fed = true
            outStatus.pointee = .haveData
            return inBuf
        }
        guard status != .error, let data = outBuf.floatChannelData else { return nil }

        let n = Int(outBuf.frameLength)
        guard n > 0 else { return nil }
        return (0..<channels).map { ch in
            Array(UnsafeBufferPointer(start: data[ch], count: n))
        }
    }
}

/// The audio-thread render core for CLAP. Allocation- and lock-free in
/// `render`; all buffers are allocated up front and freed on deinit.
final class CLAPRenderCore {
    private let host: CLAPHost
    private let inCh: Int
    private let outCh: Int
    private let maxFrames: Int

    // Planar sample data (effects only); one buffer per input channel.
    private var sampleCh: [UnsafeMutablePointer<Float>] = []
    private let sampleFrames: Int

    // Scratch input + pointer tables handed to the C shim.
    private var inScratch: [UnsafeMutablePointer<Float>] = []
    private let inPtrArray: UnsafeMutablePointer<UnsafePointer<Float>?>
    private let outPtrArray: UnsafeMutablePointer<UnsafeMutablePointer<Float>?>

    private var playhead = 0
    private var steadyTime: Int64 = 0

    init(host: CLAPHost, inputChannels: Int, outputChannels: Int, maxFrames: Int, sample: [[Float]]) {
        self.host = host
        self.inCh = inputChannels
        self.outCh = outputChannels
        self.maxFrames = maxFrames
        self.sampleFrames = sample.first?.count ?? 0

        inPtrArray  = .allocate(capacity: max(inputChannels, 1))
        outPtrArray = .allocate(capacity: max(outputChannels, 1))

        for ch in 0..<inputChannels {
            let scratch = UnsafeMutablePointer<Float>.allocate(capacity: maxFrames)
            scratch.initialize(repeating: 0, count: maxFrames)
            inScratch.append(scratch)

            let src = UnsafeMutablePointer<Float>.allocate(capacity: max(sampleFrames, 1))
            if ch < sample.count, sampleFrames > 0 {
                sample[ch].withUnsafeBufferPointer { src.update(from: $0.baseAddress!, count: sampleFrames) }
            } else if sampleFrames > 0 {
                src.initialize(repeating: 0, count: sampleFrames)
            }
            sampleCh.append(src)
        }
    }

    deinit {
        for p in inScratch { p.deallocate() }
        for p in sampleCh  { p.deallocate() }
        inPtrArray.deallocate()
        outPtrArray.deallocate()
    }

    func reset() {
        playhead = 0
        steadyTime = 0
    }

    /// Fill the output buffer list by running the plugin over `frameCount` frames.
    func render(frameCount: Int, abl: UnsafeMutablePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(abl)
        let channels = min(outCh, buffers.count)

        // Base pointer for each output channel.
        var outBase = [UnsafeMutablePointer<Float>?](repeating: nil, count: outCh)
        for ch in 0..<channels {
            outBase[ch] = buffers[ch].mData?.assumingMemoryBound(to: Float.self)
        }

        var done = 0
        while done < frameCount {
            let n = min(maxFrames, frameCount - done)

            if inCh > 0 {
                for ch in 0..<inCh {
                    let dst = inScratch[ch]
                    if sampleFrames > 0 {
                        let src = sampleCh[ch]
                        for i in 0..<n { dst[i] = src[(playhead + i) % sampleFrames] }
                    } else {
                        for i in 0..<n { dst[i] = 0 }
                    }
                    inPtrArray[ch] = UnsafePointer(dst)
                }
            }

            for ch in 0..<outCh {
                outPtrArray[ch] = (outBase[ch]).map { $0 + done }
            }

            _ = host.process(input: inCh > 0 ? UnsafePointer(inPtrArray) : nil,
                             inputChannels: inCh,
                             output: UnsafePointer(outPtrArray),
                             outputChannels: outCh,
                             frames: n,
                             steadyTime: steadyTime)

            if sampleFrames > 0 { playhead = (playhead + n) % sampleFrames }
            steadyTime += Int64(n)
            done += n
        }
    }
}
