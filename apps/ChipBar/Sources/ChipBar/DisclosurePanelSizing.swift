import CoreGraphics

enum DisclosurePanelSizing {
    static func targetHeight(documentHeight: CGFloat, contentHeightDelta: CGFloat, maximumHeight: CGFloat) -> CGFloat {
        let finalDocumentHeight = ceil(documentHeight + contentHeightDelta)
        return min(maximumHeight, max(250, finalDocumentHeight))
    }
}
