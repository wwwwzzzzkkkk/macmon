import SwiftUI

/// SwiftUI-only replacement for NSSegmentedControl. The native AppKit
/// picker used to briefly render its dark control background on navigation
/// before the glass panel's effective light/dark appearance had settled.
struct RefreshIntervalSelector: View {
    @Binding var selection: Int
    @Namespace private var highlight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let values = [1_000, 2_000, 5_000, 10_000]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(values, id: \.self) { value in
                let selected = selection == value
                Button {
                    guard selection != value else { return }
                    withAnimation(ChipBarMotion.optional(ChipBarMotion.selection,
                                                         reduceMotion: reduceMotion)) {
                        selection = value
                    }
                } label: {
                    Text("\(value / 1_000) 秒")
                        .font(.caption.weight(selected ? .semibold : .medium))
                        .foregroundStyle(selected ? Color.primary : Color.secondary)
                        .frame(maxWidth: .infinity).frame(height: 31)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(ChipBarControlTint.accent.opacity(0.17))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(ChipBarControlTint.accent.opacity(0.45), lineWidth: 0.7)
                                    }
                                    .matchedGeometryEffect(id: "refresh-selected", in: highlight)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(ChipBarPressStyle())
                .accessibilityLabel("刷新频率 \(value / 1_000) 秒")
                .accessibilityValue(selected ? "已选中" : "未选中")
            }
        }
        .padding(3)
        .background(Color.primary.opacity(0.065), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("刷新频率")
    }
}
