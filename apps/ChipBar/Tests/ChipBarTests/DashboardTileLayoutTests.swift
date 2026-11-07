import Foundation
import Testing
@testable import ChipBar

struct DashboardTileLayoutTests {
    @Test func defaultLayoutKeepsOriginalTileProportions() {
        let arrangement = DashboardTileArrangement()
        #expect(arrangement.visible == DashboardTile.allCases)
        #expect(DashboardTile.powerTrend.columns == 6)
        #expect(DashboardTile.cpu.columns == 2)
        #expect(DashboardTile.gpu.columns == 2)
        #expect(DashboardTile.memory.columns == 2)
        #expect(DashboardTile.cpuCores.columns == 6)
        #expect(DashboardTile.fan.columns == 3)
        #expect(DashboardTile.ane.columns == 3)
        #expect(DashboardTile.storage.columns == 6)
        #expect(DashboardTile.powerSupply.columns == 3)
        #expect(DashboardTile.applications.columns == 3)
    }

    @Test func corruptOrOldPreferencesCannotLoseModulesOrDuplicateTiles() {
        let arrangement = DashboardTileArrangement(
            savedOrder: ["gpu", "gpu", "unknown", "cpu"],
            savedHidden: ["ane", "ane", "unknown"])
        #expect(arrangement.order.count == DashboardTile.allCases.count)
        #expect(Set(arrangement.order).count == DashboardTile.allCases.count)
        #expect(arrangement.order.prefix(2) == [.gpu, .cpu])
        #expect(arrangement.hidden == [.ane])
    }

    @Test func draggingReordersAndNeighboringTilesFillOpenSlots() {
        var arrangement = DashboardTileArrangement()
        arrangement.move(.memory, before: .cpu)
        #expect(arrangement.visible[1] == .memory)
        #expect(arrangement.visible[2] == .cpu)
        #expect(arrangement.visible[3] == .gpu)
        arrangement.move(.powerTrend, before: .applications)
        #expect(arrangement.visible.last == .applications)
        #expect(arrangement.visible[arrangement.visible.count - 2] == .powerTrend)
    }

    @Test func visibilityCanBeChangedWithoutDestroyingSavedPosition() {
        var arrangement = DashboardTileArrangement()
        arrangement.move(.ane, before: .cpu)
        arrangement.setVisible(.ane, false)
        #expect(!arrangement.visible.contains(.ane))
        arrangement.setVisible(.ane, true)
        #expect(arrangement.visible[1] == .ane)
    }

    @Test func layoutPersistsAndResetsInDedicatedDefaults() throws {
        let suite = "chipbar.tiles.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = DashboardTileLayoutModel(defaults: defaults)
        first.move(.fan, before: .powerTrend)
        first.setVisible(.storage, false)

        let second = DashboardTileLayoutModel(defaults: defaults)
        #expect(second.visible.first == .fan)
        #expect(!second.visible.contains(.storage))
        second.reset()

        let reset = DashboardTileLayoutModel(defaults: defaults)
        #expect(reset.visible == DashboardTile.allCases)
    }
}
