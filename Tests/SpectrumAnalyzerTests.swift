import XCTest

final class SpectrumAnalyzerTests: XCTestCase {
    func testWrongWindowSizeIsSilent() {
        let bands = SpectrumAnalyzer().bands(from: [Float](repeating: 0, count: 16))
        XCTAssertEqual(bands.count, SpectrumAnalyzer.bandCount)
        XCTAssertTrue(bands.allSatisfy { $0 == 0 })
    }

    func testSilenceStaysAtZero() {
        let bands = SpectrumAnalyzer().bands(from: [Float](repeating: 0, count: SpectrumAnalyzer.fftSize))
        XCTAssertTrue(bands.allSatisfy { $0 == 0 })
    }

    func testSineWaveLightsTheMatchingBand() {
        let analyzer = SpectrumAnalyzer()
        let sampleRate = 44_100.0
        let frequency = 1_000.0
        let samples = (0..<SpectrumAnalyzer.fftSize).map { i in
            Float(sin(2 * .pi * frequency * Double(i) / sampleRate))
        }
        let bands = analyzer.bands(from: samples)
        // 1 kHz falls in the middle of the log-spaced low bands; everything must stay in range.
        XCTAssertTrue(bands.allSatisfy { $0 >= 0 && $0 <= 1 })
        XCTAssertGreaterThan(bands.prefix(6).reduce(0, +), 0)
    }
}
