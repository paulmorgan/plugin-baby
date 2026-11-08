import Foundation
import Accelerate

/// Turns a block of audio samples into a compact log-spaced magnitude spectrum
/// plus a peak level, for the audition visualizers. Runs on the audio render
/// thread, so it allocates its scratch buffers once and reuses them.
final class SpectrumAnalyzer {
    let bandCount: Int
    private let n: Int
    private let log2n: vDSP_Length
    private let fftSetup: FFTSetup
    private var window: [Float]

    // Reused scratch buffers.
    private var windowed: [Float]
    private var realp: [Float]
    private var imagp: [Float]
    private var magnitudes: [Float]
    private var bandEdges: [Int]

    init(fftSize: Int = 1024, bandCount: Int = 28) {
        self.n = fftSize
        self.bandCount = bandCount
        self.log2n = vDSP_Length(log2(Float(fftSize)))
        self.fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        self.window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        self.windowed = [Float](repeating: 0, count: fftSize)
        self.realp = [Float](repeating: 0, count: fftSize / 2)
        self.imagp = [Float](repeating: 0, count: fftSize / 2)
        self.magnitudes = [Float](repeating: 0, count: fftSize / 2)

        // Log-spaced band edges across bins 1..n/2.
        let bins = fftSize / 2
        var edges: [Int] = []
        for b in 0...bandCount {
            let frac = Double(b) / Double(bandCount)
            let bin = Int(pow(Double(bins), frac))   // 1 … bins, log-ish
            edges.append(min(max(bin, 1), bins))
        }
        self.bandEdges = edges
    }

    deinit { vDSP_destroy_fftsetup(fftSetup) }

    /// Returns peak level (0…1) and normalized band magnitudes (0…1).
    func process(_ samples: UnsafePointer<Float>, count: Int) -> (level: Float, bands: [Float]) {
        let c = min(count, n)

        // Peak level over the raw block.
        var peak: Float = 0
        vDSP_maxmgv(samples, 1, &peak, vDSP_Length(c))

        // Window (zero-pad if the block is short).
        for i in 0..<n { windowed[i] = i < c ? samples[i] * window[i] : 0 }

        realp.withUnsafeMutableBufferPointer { rp in
            imagp.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                windowed.withUnsafeBufferPointer { wp in
                    wp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) { cp in
                        vDSP_ctoz(cp, 2, &split, 1, vDSP_Length(n / 2))
                    }
                }
                vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(n / 2))
            }
        }

        // Group bins into log-spaced bands → dB → normalize to 0…1.
        var bands = [Float](repeating: 0, count: bandCount)
        let scale = 2.0 / Float(n)
        for b in 0..<bandCount {
            let lo = bandEdges[b]
            let hi = max(bandEdges[b + 1], lo + 1)
            var sum: Float = 0
            for bin in lo..<hi { sum += magnitudes[bin] }
            let mean = sum / Float(hi - lo) * scale
            // magnitudes are power; 10*log10. Map [-70, 0] dB → [0, 1].
            let db = 10 * log10f(mean + 1e-9)
            bands[b] = min(max((db + 70) / 70, 0), 1)
        }
        return (min(peak, 1), bands)
    }
}
