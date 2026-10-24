import Testing
@testable import ChipBar

struct InternalStorageSamplerTests {
    @Test func capacityIsValidWhenInternalSystemDiskIsAvailable() async {
        // CI Macs may use external/virtual boot storage. On such machines
        // the sampler must return nil rather than mislabel it "internal".
        if let capacity = await InternalStorageSampler().read() {
            #expect(capacity.totalBytes > 0)
            #expect(capacity.availableBytes >= 0)
            #expect(capacity.availableBytes <= capacity.totalBytes)
            #expect(capacity.usedFraction >= 0)
            #expect(capacity.usedFraction <= 1)
        }
    }
}
