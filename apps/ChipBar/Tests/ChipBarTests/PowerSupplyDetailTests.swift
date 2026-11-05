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

    @Test func supplyModeAdaptsToMacMiniAndMacBookPowerState() {
        func reading(hasBattery: Bool, adapter: Bool, charging: Bool,
                     watts: Double?) -> ChipBarPowerReading {
            ChipBarPowerReading(hasBattery: hasBattery, onAdapter: adapter,
                                isCharging: charging, batteryPercent: 75,
                                adapterWatts: adapter ? 65 : nil,
                                batteryWatts: watts, systemWatts: 40,
                                sourceLabel: "test", live: true)
        }

        #expect(PowerSourceMode(reading: reading(hasBattery: false, adapter: true,
                                                 charging: false, watts: nil)) == .desktop)
        #expect(PowerSourceMode(reading: reading(hasBattery: true, adapter: false,
                                                 charging: false, watts: -31)) == .battery)
        #expect(PowerSourceMode(reading: reading(hasBattery: true, adapter: true,
                                                 charging: true, watts: 20)) == .adapterCharging)
        #expect(PowerSourceMode(reading: reading(hasBattery: true, adapter: true,
                                                 charging: false, watts: 0)) == .adapter)
        #expect(PowerSourceMode(reading: reading(hasBattery: true, adapter: true,
                                                 charging: false, watts: -5)) == .adapterAssisted)
        #expect(SidePanelLayout.height(for: .power, powerMode: .adapterCharging)
                > SidePanelLayout.height(for: .power, powerMode: .desktop))
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
