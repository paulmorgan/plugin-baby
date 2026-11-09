import Foundation
import AVFoundation

/// Taps a mixer node, runs each buffer through a `SpectrumAnalyzer`, and
/// publishes `(peakLevel, bands)` on the main actor. Shared by the AU and CLAP
/// audition backends, which both meter their `mainMixerNode` the same way.
///
/// The analyzer runs on the audio-tap thread; the published callback hops to the
/// main actor for the UI. `remove()` emits one final zeroed update so the meters
/// settle to rest.
@MainActor
final class MeterTap {
    private let analyzer: SpectrumAnalyzer
    private weak var tappedNode: AVAudioMixerNode?

    /// Called on the main actor with (peak level 0…1, spectrum bands) per buffer,
    /// and once with zeros when the tap is removed.
    var onMeter: ((Float, [Float]) -> Void)?

    init(fftSize: Int = 1024, bandCount: Int = 28) {
        analyzer = SpectrumAnalyzer(fftSize: fftSize, bandCount: bandCount)
    }

    var bandCount: Int { analyzer.bandCount }
    var isActive: Bool { tappedNode != nil }

    func install(on node: AVAudioMixerNode) {
        guard tappedNode == nil else { return }
        let analyzer = self.analyzer
        node.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            guard let channels = buffer.floatChannelData else { return }
            let frames = Int(buffer.frameLength)
            let (level, bands) = analyzer.process(channels[0], count: frames)
            Task { @MainActor in self?.onMeter?(level, bands) }
        }
        tappedNode = node
    }

    func remove() {
        guard let node = tappedNode else { return }
        node.removeTap(onBus: 0)
        tappedNode = nil
        onMeter?(0, Array(repeating: 0, count: analyzer.bandCount))
    }
}
