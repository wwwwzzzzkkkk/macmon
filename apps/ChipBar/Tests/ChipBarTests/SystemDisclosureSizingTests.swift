import CoreGraphics
import Testing
@testable import ChipBar

struct SystemDisclosureSizingTests {
    @Test func firstExpansionDoesNotWaitForSwiftUILayout() {
        // Real content can be long; the first click immediately animates to
        // screen height. Only after settling is the exact size measured.
        #expect(SystemDisclosureSizing.targetHeight(
            expanding: true, currentHeight: 590,
            previouslyCollapsed: nil, previouslyExpanded: nil,
            maximumHeight: 820
        ) == 820)
    }

    @Test func collapseUsesPreviouslyMeasuredCollapsedDocument() {
        #expect(SystemDisclosureSizing.targetHeight(
            expanding: false, currentHeight: 1_230,
            previouslyCollapsed: 620, previouslyExpanded: 1_230,
            maximumHeight: 820
        ) == 620)
    }

    @Test func subsequentExpansionUsesMeasuredDestination() {
        #expect(SystemDisclosureSizing.targetHeight(
            expanding: true, currentHeight: 520,
            previouslyCollapsed: 520, previouslyExpanded: 720,
            maximumHeight: 820
        ) == 720)
    }

    @Test func screenCapAndMinimumProtectSmallScreens() {
        #expect(SystemDisclosureSizing.targetHeight(
            expanding: true, currentHeight: 620,
            previouslyCollapsed: 620, previouslyExpanded: 1_500,
            maximumHeight: 850
        ) == 850)
        #expect(SystemDisclosureSizing.targetHeight(
            expanding: false, currentHeight: 450,
            previouslyCollapsed: 175, previouslyExpanded: 450,
            maximumHeight: 850
        ) == 250)
    }
}
