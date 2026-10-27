import CoreGraphics

enum DisclosurePanelSizing {
    /// The return trip must use the cached home height. Measuring only after
    /// the page slides would serialize two separate animations and stutter.
    static func navigationHeight(enteringSettings: Bool,
                                 currentHeight: CGFloat,
                                 homeHeight: CGFloat?,
                                 settingsHeight: CGFloat?,
                                 maximumHeight: CGFloat) -> CGFloat {
        let proposal = enteringSettings
            ? (settingsHeight ?? maximumHeight)
            : (homeHeight ?? currentHeight)
        return min(maximumHeight, max(250, proposal))
    }

    /// Recover the stable fully-collapsed document height from the last
    /// settled layout. While a panel animation is in progress, keep reusing
    /// that baseline: measuredHeight intentionally does not track each frame.
    static func collapsedDocumentHeight(measuredHeight: CGFloat, applications: Double,
                                        ssd: Double, ssdDetailsHeight: CGFloat) -> CGFloat {
        max(0, measuredHeight - CGFloat(applications) * 104
            - CGFloat(ssd) * max(0, ssdDetailsHeight))
    }

    /// Interruption-safe destination. Retarget directly from the same baseline
    /// rather than subtracting from a stale previous window/document height.
    static func expandedDocumentHeight(collapsedHeight: CGFloat, applications: Double,
                                       ssd: Double, ssdDetailsHeight: CGFloat) -> CGFloat {
        max(250, collapsedHeight + CGFloat(applications) * 104
            + CGFloat(ssd) * max(0, ssdDetailsHeight))
    }

    static func targetHeight(documentHeight: CGFloat, contentHeightDelta: CGFloat, maximumHeight: CGFloat) -> CGFloat {
        let finalDocumentHeight = ceil(documentHeight + contentHeightDelta)
        return min(maximumHeight, max(250, finalDocumentHeight))
    }
}
