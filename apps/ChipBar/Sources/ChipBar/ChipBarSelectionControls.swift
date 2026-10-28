import SwiftUI
import ChipBarCore

/// Subtle, monochrome selection affordance shared by preferences and menu
/// items. The thumb moves within a fixed track; no checkmark, no blue accent,
/// and no intrinsic-size changes when the state updates.
struct ChipBarMiniSwitch: View {
    let enabled: Bool
    var compact: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var trackWidth: CGFloat { compact ? 29 : 36 }
    private var trackHeight: CGFloat { compact ? 17 : 21 }
    private var thumbSize: CGFloat { compact ? 11 : 15 }
    private var thumbTravel: CGFloat { (trackWidth - thumbSize) / 2 - 3 }

    var body: some View {
        Capsule()
            .fill(Color.primary.opacity(enabled ? 0.19 : 0.075))
            .overlay {
                Capsule()
                    .strokeBorder(Color.primary.opacity(enabled ? 0.25 : 0.11),
                                  lineWidth: 0.8)
            }
            .overlay {
                Circle()
                    .fill(enabled ? Color.primary : Color.secondary.opacity(0.66))
                    .frame(width: thumbSize, height: thumbSize)
                    .offset(x: enabled ? thumbTravel : -thumbTravel)
                    .animation(ChipBarMotion.optional(ChipBarMotion.selection,
                                                      reduceMotion: reduceMotion),
                               value: enabled)
            }
            .frame(width: trackWidth, height: trackHeight)
            .accessibilityHidden(true)
    }
}

/// Keep real Toggle bindings, including existing UserDefaults persistence,
/// while replacing the system's bright-blue switch/checkmark with a quiet
/// glass-style control. Entire row remains an accessible, clickable target.
struct ChipBarGlassToggleStyle: ToggleStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(ChipBarMotion.optional(ChipBarMotion.selection,
                                                 reduceMotion: reduceMotion)) {
                configuration.isOn.toggle()
            }
        } label: {
            HStack(spacing: 10) {
                configuration.label
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                ChipBarMiniSwitch(enabled: configuration.isOn)
            }
            .padding(.horizontal, 11)
            .frame(height: 39)
            .background(Color.primary.opacity(configuration.isOn ? 0.09 : 0.035),
                        in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.primary.opacity(configuration.isOn ? 0.18 : 0.07),
                                  lineWidth: 0.7)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(ChipBarPressStyle())
        .accessibilityValue(configuration.isOn ? "已开启" : "已关闭")
        .accessibilityHint("点击切换")
    }
}

/// The power menu selector uses the same neutral selected surface as the
/// refresh-frequency selector, avoiding native menu checkmarks.
struct ChipBarPowerSelection: View {
    @Binding var selection: PowerMetric

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var highlight

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("菜单栏功率")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 2) {
                ForEach(PowerMetric.allCases) { metric in
                    let selected = metric == selection
                    Button {
                        guard !selected else { return }
                        withAnimation(ChipBarMotion.optional(ChipBarMotion.selection,
                                                             reduceMotion: reduceMotion)) {
                            selection = metric
                        }
                    } label: {
                        Text(metric.title)
                            .font(.caption.weight(selected ? .semibold : .medium))
                            .foregroundStyle(selected ? Color.primary : Color.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                            .frame(height: 30)
                            .background {
                                if selected {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.primary.opacity(0.13))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 8)
                                                .strokeBorder(Color.primary.opacity(0.12),
                                                              lineWidth: 0.5)
                                        }
                                        .matchedGeometryEffect(id: "power-selected", in: highlight)
                                }
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(ChipBarPressStyle())
                    .accessibilityLabel("菜单栏功率 \(metric.title)")
                    .accessibilityValue(selected ? "已选中" : "未选中")
                }
            }
            .padding(3)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        }
        .accessibilityElement(children: .contain)
    }
}
