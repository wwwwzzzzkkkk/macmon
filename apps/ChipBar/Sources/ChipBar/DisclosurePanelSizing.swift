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

    static func targetHeight(documentHeight: CGFloat, contentHeightDelta: CGFloat, maximumHeight: CGFloat) -> CGFloat {
        let finalDocumentHeight = ceil(documentHeight + contentHeightDelta)
        return min(maximumHeight, max(250, finalDocumentHeight))
    }
}
