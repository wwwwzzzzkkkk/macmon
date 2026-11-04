import Foundation
import Testing
@testable import ChipBar

struct PowerSupplyDetailTests {
    @Test func internalRailDifferenceIsCalculatedOnlyWhenValid() {
        let normal = PowerDistribution(internalWatts: 25, chipWatts: 16)
        #expect(normal.otherWatts == 9)
        #expect(normal.chipFraction == 0.64)
        #expect(normal.otherFraction == 0.36)
    }

    @Test func missingOrContradictoryReadingsAreNotFaked() {
        let missing = PowerDistribution(internalWatts: nil, chipWatts: 16)
        #expect(missing.otherWatts == nil)
        #expect(missing.chipFraction == nil)
        let contradiction = PowerDistribution(internalWatts: 12, chipWatts: 20)
        #expect(contradiction.otherWatts == nil)
        #expect(contradiction.chipFraction == nil)
        let negative = PowerDistribution(internalWatts: -5, chipWatts: 2)
        #expect(negative.otherWatts == nil)
    }
}
