import SwiftUI

/// A bounded percentage indicator for utilization and memory only.
/// Power readings are intentionally not normalised against an arbitrary wattage.
struct MetricRing: View {
    let title: String
    let percentage: Double?
    let tint: Color
    /// Optional memory pressure status and RAM usage, shown in the compact
    /// ring itself instead of an additional full-width memory row.
    var status: String? = nil
    var detail: String? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var fraction: Double {
        guard let percentage, percentage.isFinite else { return 0 }
        return min(1, max(0, percentage / 100))
    }

    private var motion: Animation {
        reduceMotion ? .linear(duration: 0) : .spring(response: 0.55, dampingFraction: 0.84)
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.10), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: CGFloat(fraction))
                    .stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(motion, value: fraction)
                if percentage != nil, percentage?.isFinite == true {
                    AnimatedPercentage(value: fraction * 100)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .animation(motion, value: fraction)
                } else {
                    Text("—").font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 52, height: 52)
            .accessibilityHidden(true)
            // Keep a single fixed caption line under every ring, including
            // CPU and GPU: the three circular gauges always share a baseline.
            Text(detail ?? status ?? " ")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(height: 12)
                .help([status, detail].compactMap { $0 }.joined(separator: " · "))
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .frame(height: 84, alignment: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)：\(percentage.map { String(format: "%.0f%%", $0) } ?? "不可用")" +
                            (status.map { "，内存压力\($0)" } ?? "") +
                            (detail.map { "，\($0)" } ?? ""))
    }
}

/// Animatable numerical text shares the ring's spring timeline, so the number
/// doesn't jump to the new sample before the stroke catches up.
private struct AnimatedPercentage: View, Animatable {
    var value: Double

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(String(format: "%.0f%%", value))
    }
}
