import Dispatch
import Testing
@testable import ChipBar

@MainActor struct MemoryPressureTests {
    @Test func mapsSystemPressureEventsToStatusLevels() {
        #expect(Monitor.memoryPressureLevel(for: .normal) == .normal)
        #expect(Monitor.memoryPressureLevel(for: .warning) == .warning)
        #expect(Monitor.memoryPressureLevel(for: .critical) == .critical)
        #expect(Monitor.memoryPressureLevel(for: []) == .unknown)
    }

    @Test func combinedEventsKeepTheMoreUrgentPressureLevel() {
        #expect(Monitor.memoryPressureLevel(for: [.normal, .warning]) == .warning)
        #expect(Monitor.memoryPressureLevel(for: [.normal, .critical]) == .critical)
    }

    @Test func mapsInitialSystemLevelAndRejectsUnknownKernelValues() {
        #expect(Monitor.memoryPressureLevel(forSystemValue: 1) == .normal)
        #expect(Monitor.memoryPressureLevel(forSystemValue: 2) == .warning)
        #expect(Monitor.memoryPressureLevel(forSystemValue: 4) == .critical)
        #expect(Monitor.memoryPressureLevel(forSystemValue: 0) == nil)
    }
}
