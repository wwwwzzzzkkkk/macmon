import CoreGraphics
import Testing
@testable import ChipBar

struct DisclosurePanelSizingTests {
    @Test func collapseUsesFullDocumentHeightWhenExpandedWindowWasScreenCapped() {
        // The expanded document is 1,000 pt tall, but the visible panel was
        // capped at 800 pt. Closing a 300 pt section should target 700 pt.
        #expect(DisclosurePanelSizing.targetHeight(
            documentHeight: 1_000,
            contentHeightDelta: -300,
            maximumHeight: 800
        ) == 700)
    }

    @Test func expansionRemainsCappedAndSmallPanelsKeepTheirMinimumHeight() {
        #expect(DisclosurePanelSizing.targetHeight(
            documentHeight: 700,
            contentHeightDelta: 400,
            maximumHeight: 800
        ) == 800)
        #expect(DisclosurePanelSizing.targetHeight(
            documentHeight: 280,
            contentHeightDelta: -100,
            maximumHeight: 800
        ) == 250)
    }
}
