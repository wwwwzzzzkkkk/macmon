import Foundation
import Testing
@testable import ChipBar

@MainActor struct PanelLayoutCoordinatorTests {
    @Test func burstsOfSamplesTriggerOneGeometryRefresh() async throws {
        var invocations = 0
        let coordinator = PanelLayoutCoordinator { invocations += 1 }
        for _ in 0..<30 { coordinator.request() }
        try await Task.sleep(for: .milliseconds(330))
        #expect(invocations == 1)
        #expect(coordinator.requests == 30)
        #expect(coordinator.applied == 1)
        coordinator.cancelPending()
    }

    @Test func aScrollingViewportDoesNotRefitMidGesture() async throws {
        var invocations = 0
        let coordinator = PanelLayoutCoordinator { invocations += 1 }
        coordinator.noteScroll()
        coordinator.request()
        try await Task.sleep(for: .milliseconds(210))
        #expect(invocations == 0)
        try await Task.sleep(for: .milliseconds(240))
        #expect(invocations == 1)
        coordinator.cancelPending()
    }

    @Test func canceledSizingCannotOverwriteNewPageGeometry() async throws {
        var invocations = 0
        let coordinator = PanelLayoutCoordinator { invocations += 1 }
        coordinator.request()
        coordinator.cancelPending()
        try await Task.sleep(for: .milliseconds(300))
        #expect(invocations == 0)
    }
}
