import SwiftUI

/// Interpolate the displayed number rather than snapping text while the
/// adjacent ring springs to the new sample. Fixed width/monospaced digits
/// prevent neighboring controls from shifting while values change.
struct AnimatedMetricValue: View, Animatable {
    var value: Double?
    var decimals: Int = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var animatableData: Double {
        get { value ?? 0 }
        set {
            if value != nil { value = newValue }
        }
    }

    var body: some View {
        Text(value.flatMap { $0.isFinite ? String(format: "%.*f", decimals, $0) : nil } ?? "—")
            .monospacedDigit()
            .animation(reduceMotion ? nil : ChipBarMotion.selection, value: value)
    }
}

struct PowerMetricCard: View {
    let title: String
    let power: Double?
    let connected: Bool
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                AnimatedMetricValue(value: connected ? power : nil)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                Text("W").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 11))
        .accessibilityElement(children: .combine)
    }
}

/// Shared compact progress component for internal disk / future SSD cards.
/// Avoids GeometryReader's default infinite ideal height by fixing it to 4 pt.
struct CapacityProgressTrack: View {
    let usedFraction: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var fraction: Double {
        guard let usedFraction, usedFraction.isFinite else { return 0 }
        return max(0, min(1, usedFraction))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.10))
                Capsule().fill(Color(red: 0.22, green: 0.65, blue: 0.79).opacity(0.70))
                    .frame(width: geometry.size.width * fraction)
            }
        }
        .frame(height: 4)
        .animation(reduceMotion ? nil : ChipBarMotion.disclosure, value: fraction)
        .accessibilityHidden(true)
    }
}
