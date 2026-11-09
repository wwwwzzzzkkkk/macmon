import Testing
@testable import ChipBar

struct USBCPowerReaderTests {
    private func port(_ id: String, watts: Double?) -> USBCPortMeasurement {
        USBCPortMeasurement(
            id: id, label: id, number: nil,
            isConnected: true, protocolName: "USB 3.x",
            maximumGbps: 10, currentGbps: nil,
            voltage: nil, current: nil, watts: watts
        )
    }

    @Test func normalizedUUIDRejectsMissingOrMalformedIdentifiers() {
        #expect(USBCPowerReader.normalisedUUID(nil) == nil)
        #expect(USBCPowerReader.normalisedUUID("invalid") == nil)
        #expect(USBCPowerReader.normalisedUUID("B918D52A-F329-3551-66A6-2B5FDC393D64")
            == "b918d52af329355166a62b5fdc393d64")
    }

    @Test func outputSumExcludesUnavailableMeasurements() {
        let sample = USBCPowerSnapshot(ports: [
            port("a", watts: 6.24), port("b", watts: 3.07),
            port("unknown", watts: nil)
        ])
        #expect(abs((sample.totalWatts ?? 0) - 9.31) < 0.001)
        #expect(sample.sourcingPorts.map(\.id) == ["a", "b"])
        #expect(USBCPowerSnapshot(ports: [port("a", watts: nil)]).totalWatts == nil)
        #expect(USBCPowerSnapshot(ports: [port("a", watts: 0)]).totalWatts == 0)
    }

    @Test func linkLabelsKeepCapabilitySeparateFromAchievedRate() {
        #expect(USBCFormat.speed(nil) == "未提供")
        #expect(USBCFormat.speed(0.48) == "480 Mb/s")
        #expect(USBCFormat.speed(40) == "40 Gb/s")
        #expect(USBCFormat.watts(nil, precision: 2) == "—")
    }
}
