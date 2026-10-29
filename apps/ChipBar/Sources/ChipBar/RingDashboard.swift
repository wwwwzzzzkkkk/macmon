import SwiftUI
import ChipBarCore

/// The original ChipBar circular runway, promoted to the dashboard's primary
/// visual element.  All three gauges use the same geometry and animated arc.
struct DashboardRunway: View {
    let title: String
    let percentage: Double?
    let color: Color
    let subtitle: String
    let detail: String
    var pressureStatus: String? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var fraction: Double {
        guard let percentage, percentage.isFinite else { return 0 }
        return max(0, min(1, percentage / 100))
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.095), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? nil :
                        .spring(response: 0.55, dampingFraction: 1.0), value: fraction)

                VStack(spacing: 2) {
                    Text(title)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    if percentage?.isFinite == true {
                        RunwayPercentage(value: fraction * 100)
                            .font(.system(size: 19, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .animation(reduceMotion ? nil :
                                .spring(response: 0.55, dampingFraction: 1.0), value: fraction)
                    } else {
                        Text("—")
                            .font(.system(size: 19, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 80, height: 80)
            .accessibilityHidden(true)

            Text(subtitle)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(height: 17)
            Text(detail)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(height: 13)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)，\(percentage.map { String(format: "%.0f%%", $0) } ?? "占用不可用")，\(subtitle)，\(detail)" +
                            (pressureStatus.map { "，内存压力\($0)" } ?? ""))
    }
}

private struct RunwayPercentage: View, Animatable {
    var value: Double

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(String(format: "%.0f%%", value))
    }
}

/// The Neural Engine has a real power reading but no trustworthy aggregate
/// utilization counter.  Keep it as a separate, quiet metric instead of
/// displaying RAM utilization under an ANE heading.
struct DashboardANEStrip: View {
    let power: Double?
    let connected: Bool

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "sparkle")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color(red: 0.22, green: 0.65, blue: 0.79))
                .frame(width: 24)
            Text("ANE")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text("神经网络引擎功率")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                AnimatedMetricValue(value: connected ? power : nil)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                Text("W")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}
