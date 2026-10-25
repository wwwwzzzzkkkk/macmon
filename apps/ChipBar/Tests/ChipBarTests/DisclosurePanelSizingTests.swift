import CoreGraphics
import Testing
@testable import ChipBar

struct DisclosurePanelSizingTests {
    @Test func settingsReturnUsesPreviouslyMeasuredHomeWithoutTwoPhaseResize() {
        let home: CGFloat = 582
        // Settings was screen-capped to 810 while editing preferences.
        #expect(DisclosurePanelSizing.navigationHeight(
            enteringSettings: false, currentHeight: 940,
            homeHeight: home, settingsHeight: 940, maximumHeight: 810
        ) == 582)
        #expect(DisclosurePanelSizing.navigationHeight(
            enteringSettings: true, currentHeight: home,
            homeHeight: home, settingsHeight: nil, maximumHeight: 810
        ) == 810)
    }

    @Test func navigationUsesExactCachedSizesAndRespectsScreenCap() {
        #expect(DisclosurePanelSizing.navigationHeight(
            enteringSettings: true, currentHeight: 650,
            homeHeight: 650, settingsHeight: 710, maximumHeight: 850
        ) == 710)
        #expect(DisclosurePanelSizing.navigationHeight(
            enteringSettings: false, currentHeight: 710,
            homeHeight: 900, settingsHeight: 710, maximumHeight: 750
        ) == 750)
    }

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
