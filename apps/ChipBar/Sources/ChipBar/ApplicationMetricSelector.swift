import SwiftUI

/// Four-way selector designed for a small native glass popover. Unlike an
/// NSSegmentedControl, the selected surface travels on one interrupted spring
/// and never changes the height of the containing application ranking.
struct ApplicationMetricSelector: View {
    @Binding var selection: ApplicationResource
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 1) {
            ForEach(ApplicationResource.allCases) { metric in
                let selected = selection == metric
                Button {
                    guard selection != metric else { return }
                    withAnimation(ChipBarMotion.optional(ChipBarMotion.selection,
                                                         reduceMotion: reduceMotion)) {
                        selection = metric
                    }
                } label: {
                    Text(metric.rawValue)
                        .font(.subheadline.weight(selected ? .semibold : .medium))
                        .monospacedDigit()
                        .foregroundStyle(selected ? Color.primary : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 33)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.primary.opacity(0.15))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                                    }
                                    .matchedGeometryEffect(id: "selectedMetric", in: highlight)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(ChipBarPressStyle())
                .help("查看应用\(metric.rawValue)占用")
                .accessibilityLabel("\(metric.rawValue) 应用占用")
                .accessibilityValue(selected ? "已选中" : "未选中")
            }
        }
        .padding(3)
        .background(Color.primary.opacity(0.075), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
        }
        // The tap already supplies one spring transaction to the matched
        // highlight. A second implicit animation on the whole selector
        // reanimated its text and could cause an extra hop after rapid taps.
        .accessibilityElement(children: .contain)
        .accessibilityLabel("应用占用指标")
    }
}
