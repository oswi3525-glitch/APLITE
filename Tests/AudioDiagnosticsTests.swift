import XCTest

/// Pure logic of the audio diagnostics. These tests run without a host app and without an audio
/// device: they cover the event ring buffer, route classification and the report format that
/// Settings / DebugScript expose. Live AVAudioSession behaviour is verified on a device (see BUILD.md).
final class AudioDiagnosticsTests: XCTestCase {
    private func snapshot(outputs: [AudioPortSummary] = [], inputs: [AudioPortSummary] = []) -> AudioSnapshot {
        AudioSnapshot(category: "AVAudioSessionCategoryPlayback", mode: "AVAudioSessionModeDefault",
                      options: ["MixWithOthers"], isActive: true, outputVolume: 0.7,
                      sampleRate: 48000, ioBufferDuration: 0.01,
                      outputs: outputs, inputs: inputs, timestamp: Date(timeIntervalSince1970: 1_700_000_000))
    }

    func testEventLogIsBounded() {
        var log = AudioEventLog(limit: 3)
        for i in 0..<10 { log.append(AudioEvent(kind: .route, message: "event \(i)")) }
        XCTAssertEqual(log.events.count, 3, "the log must not grow without limit")
        XCTAssertEqual(log.events.first?.message, "event 7")
        XCTAssertEqual(log.events.last?.message, "event 9")
        log.clear()
        XCTAssertTrue(log.events.isEmpty)
    }

    func testEventLineCarriesKindAndMessage() {
        let event = AudioEvent(kind: .interruption, message: "Interruption ended")
        XCTAssertTrue(event.line.contains("[interruption]"))
        XCTAssertTrue(event.line.contains("Interruption ended"))
    }

    func testPortClassification() {
        XCTAssertTrue(AudioPortSummary.isHeadphones("Headphones"))
        XCTAssertTrue(AudioPortSummary.isHeadphones("BluetoothHFP") == false)
        XCTAssertTrue(AudioPortSummary.isHeadphones("USBAudio"))
        XCTAssertFalse(AudioPortSummary.isHeadphones("BuiltInSpeaker"))
    }

    func testRouteFlagsForSpeakerHeadphonesAndDisplay() {
        let speaker = snapshot(outputs: [AudioPortSummary(portType: "BuiltInSpeaker", name: "iPhone Speaker")])
        XCTAssertTrue(speaker.hasBuiltInSpeaker)
        XCTAssertFalse(speaker.hasHeadphones)

        let bt = snapshot(outputs: [AudioPortSummary(portType: "BluetoothA2DPOutput", name: "AirPods")],
                          inputs: [AudioPortSummary(portType: "BluetoothHFP", name: "AirPods Mic")])
        XCTAssertTrue(bt.hasBluetooth)
        XCTAssertFalse(bt.hasBuiltInSpeaker)

        let hdmi = snapshot(outputs: [AudioPortSummary(portType: "HDMI", name: "TV")])
        XCTAssertTrue(hdmi.hasHDMI)
        XCTAssertTrue(hdmi.routeDescription.contains("TV (HDMI)"))
    }

    func testReportContainsSessionFacts() {
        let report = snapshot(outputs: [AudioPortSummary(portType: "AirPlay", name: "Apple TV")])
            .report(preamble: "APLite audio diagnostics")
        XCTAssertTrue(report.contains("APLite audio diagnostics"))
        XCTAssertTrue(report.contains("AVAudioSessionCategoryPlayback"))
        XCTAssertTrue(report.contains("MixWithOthers"))
        XCTAssertTrue(report.contains("Active: yes"))
        XCTAssertTrue(report.contains("48000 Hz"))
        XCTAssertTrue(report.contains("AirPlay=yes"))
        XCTAssertTrue(report.contains("Output: Apple TV (AirPlay)"))
    }
}
