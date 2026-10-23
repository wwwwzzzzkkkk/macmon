import Darwin
import Testing
@testable import ChipBar

struct ApplicationMemoryReadTests {
    @Test func currentProcessMustHaveNonzeroMemory() {
        // Core-only fixtures cannot detect an OS returning 0 for every
        // ri_phys_footprint. Run the real reader on the macOS CI machine.
        let reading = ProcessMemoryReader.read(pid: getpid(), initialFootprint: nil)
        #expect(reading.bytes != nil)
        #expect((reading.bytes ?? 0) > 1_000_000)
    }

    @Test func knownFootprintIsPreferredWithoutApproximation() {
        let reading = ProcessMemoryReader.read(pid: getpid(), initialFootprint: 128_000_000)
        #expect(reading.bytes == 128_000_000)
        #expect(!reading.approximate)
    }

    @Test func invalidProcessDoesNotCreateFakeMemory() {
        let reading = ProcessMemoryReader.read(pid: -1, initialFootprint: nil)
        #expect(reading.bytes == nil)
        #expect(!reading.approximate)
    }

    @Test func liveApplicationScanContainsNonzeroMemory() async {
        let snapshot = await ApplicationActivitySampler().sample()
        #expect(snapshot.readableMemoryCount > 0)
        #expect(snapshot.rows.contains { ($0.physicalBytes ?? 0) > 1_000_000 })
    }
}
