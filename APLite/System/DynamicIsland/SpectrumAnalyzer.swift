import Foundation
import Accelerate

/// Real-time FFT over a sliding PCM window. Pure logic (no UIKit), so it can be unit tested without a host app.
/// Kept off the main thread by `AudioSpectrumProvider`.
final class SpectrumAnalyzer {
    static let fftSize = 1024
    static let bandCount = 12

    private let log2Size = vDSP_Length(log2(Float(SpectrumAnalyzer.fftSize)))
    private let setup: FFTSetup
    private let window: [Float]

    init() {
        setup = vDSP_create_fftsetup(log2Size, FFTRadix(kFFTRadix2))!
        var hann = [Float](repeating: 0, count: SpectrumAnalyzer.fftSize)
        vDSP_hann_window(&hann, vDSP_Length(hann.count), 1)
        window = hann
    }

    deinit { vDSP_destroy_fftsetup(setup) }

    /// Maps a mono float PCM window onto `bandCount` log-spaced, normalised (0…1) magnitudes.
    func bands(from samples: [Float]) -> [Float] {
        guard samples.count == SpectrumAnalyzer.fftSize else {
            return Array(repeating: 0, count: SpectrumAnalyzer.bandCount)
        }

        var windowed = [Float](repeating: 0, count: SpectrumAnalyzer.fftSize)
        vDSP_vmul(samples, 1, window, 1, &windowed, 1, vDSP_Length(SpectrumAnalyzer.fftSize))

        var real = [Float](repeating: 0, count: SpectrumAnalyzer.fftSize / 2)
        var imag = [Float](repeating: 0, count: SpectrumAnalyzer.fftSize / 2)
        var split = DSPSplitComplex(realp: &real, imagp: &imag)
        windowed.withUnsafeBufferPointer { source in
            source.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: SpectrumAnalyzer.fftSize / 2) { complex in
                vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(SpectrumAnalyzer.fftSize / 2))
            }
        }
        vDSP_fft_zrip(setup, &split, 1, log2Size, FFTDirection(kFFTDirection_Forward))

        var magnitudes = [Float](repeating: 0, count: SpectrumAnalyzer.fftSize / 2)
        vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(magnitudes.count))

        var result = [Float](repeating: 0, count: SpectrumAnalyzer.bandCount)
        let low = 1, high = 256
        for band in 0..<SpectrumAnalyzer.bandCount {
            let from = Int(pow(Double(high / low), Double(band) / Double(SpectrumAnalyzer.bandCount)) * Double(low))
            let to = Int(pow(Double(high / low), Double(band + 1) / Double(SpectrumAnalyzer.bandCount)) * Double(low))
            guard from < magnitudes.count else { break }
            let end = min(max(to, from + 1), magnitudes.count)
            var peak: Float = 0
            let slice = Array(magnitudes[from..<end])
            vDSP_maxv(slice, 1, &peak, vDSP_Length(slice.count))
            result[band] = min(1, sqrt(max(0, peak)) / 600)
        }
        return result
    }
}
