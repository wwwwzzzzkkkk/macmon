import Foundation
import Testing
@testable import ChipBar
import ChipBarCore

@MainActor struct StorageCapacityPresentationTests {
    @Test func skipsInternalVolumesAndDoesNotAddSharedAPFSCapacity() throws {
        let data = try #require(DiskVolumeSpace(id: "/Volumes/Data",
                                              name: "External Data",
                                              total: 1_000_000_000_000,
                                              available: 350_000_000_000, apfs: true))
        let system = try #require(DiskVolumeSpace(id: "/Volumes/ExternalSystem",
                                                name: "External System",
                                                total: 1_000_000_000_000,
                                                available: 350_000_000_000, apfs: true))
        let systemVolume = try #require(DiskVolumeSpace(id: "/System/Volumes/Data",
                                                  name: "Internal",
                                                  total: 512_000_000_000,
                                                  available: 90_000_000_000, apfs: true))
        let snapshot = DiskActivitySnapshot(
            volumes: ["disk5": [data, system], "disk0": [systemVolume]],
            connected: ["disk5", "disk0"],
            external: ["disk5"]
        )
        let rows = ExternalStorageCapacityModel.displayRows(from: snapshot)
        #expect(rows.count == 1)
        #expect(rows.first?.diskID == "disk5")
        #expect(rows.first?.volume.available == 350_000_000_000)
        #expect(rows.first?.volume.total == 1_000_000_000_000)
    }

    @Test func preservesIndependentMountedExternalVolumes() throws {
        let first = try #require(DiskVolumeSpace(id: "/Volumes/Backup", name: "Backup",
                                                total: 300_000_000_000,
                                                available: 150_000_000_000, apfs: false))
        let second = try #require(DiskVolumeSpace(id: "/Volumes/Media", name: "Media",
                                                 total: 200_000_000_000,
                                                 available: 50_000_000_000, apfs: false))
        let snapshot = DiskActivitySnapshot(
            volumes: ["disk4": [first], "disk5": [second]],
            connected: ["disk4", "disk5"],
            external: ["disk4", "disk5"]
        )
        let rows = ExternalStorageCapacityModel.displayRows(from: snapshot)
        #expect(rows.count == 2)
        #expect(Set(rows.map(\.id)) == [first.id, second.id])
    }

    @Test func noExternalDrivesProducesEmptyCardInsteadOfInternalGuess() {
        let snapshot = DiskActivitySnapshot()
        #expect(ExternalStorageCapacityModel.displayRows(from: snapshot).isEmpty)
    }
}
