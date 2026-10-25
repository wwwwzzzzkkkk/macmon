import CoreGraphics

/// Predict the NSPanel destination immediately at the moment of a toggle.
/// The natural SwiftUI height is measured once AFTER animation and cached.
/// On the first expansion, default to available screen height rather than
/// delaying the click response for a potentially expensive fittingSize pass.
enum SystemDisclosureSizing {
    static func targetHeight(expanding: Bool,
                             currentHeight: CGFloat,
                             previouslyCollapsed: CGFloat?,
                             previouslyExpanded: CGFloat?,
                             maximumHeight: CGFloat) -> CGFloat {
        let proposal = expanding
            ? (previouslyExpanded ?? maximumHeight)
            : (previouslyCollapsed ?? currentHeight)
        return min(maximumHeight, max(250, proposal))
    }
}
