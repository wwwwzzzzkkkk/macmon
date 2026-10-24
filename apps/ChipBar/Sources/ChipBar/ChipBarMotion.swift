import SwiftUI
import QuartzCore

/// A single motion language for ChipBar 2.0.
/// Short, interrupted gestures should not stack expensive layout animations.
/// Respect Reduce Motion throughout the dashboard.
enum ChipBarMotion {
    static let tap = Animation.spring(response: 0.24, dampingFraction: 0.76)
    static let disclosure = Animation.spring(response: 0.35, dampingFraction: 0.88)
    static let selection = Animation.spring(response: 0.30, dampingFraction: 0.84)
    static let navigation = Animation.easeInOut(duration: 0.24)

    static func optional(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}

/// Transient press animation does not remount the button or resize its parent.
/// It covers all normal dashboard buttons (settings, back, pause, selectors).
struct ChipBarPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.965 : 1))
            .opacity(configuration.isPressed && !reduceMotion ? 0.78 : 1)
            .animation(ChipBarMotion.optional(.spring(response: 0.22, dampingFraction: 0.72),
                                              reduceMotion: reduceMotion),
                       value: configuration.isPressed)
    }
}

/// The same restrained disclosure affordance throughout AppKit/SwiftUI.
/// Chevron rotation is animated by the state change, not by polling samples.
struct ChipBarSectionToggle: View {
    let title: String
    let systemImage: String
    let expanded: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Label(title, systemImage: systemImage)
                    .font(.subheadline.weight(.medium))
                Spacer(minLength: 6)
                Text(expanded ? "收起" : "展开")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .rotationEffect(.degrees(expanded ? 180 : 0))
                    .animation(ChipBarMotion.optional(ChipBarMotion.disclosure,
                                                      reduceMotion: reduceMotion), value: expanded)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(ChipBarPressStyle())
        .accessibilityLabel("\(title)，\(expanded ? "收起" : "展开")")
    }
}
