import SwiftUI

/// The aggregate chip total comes from the SAME sample shown on Home.
/// Inconsistent/negative derived numbers are unavailable, never clamped
/// into made-up wattage values.
struct PowerDistribution {
    let internalWatts: Double?
    let chipWatts: Double?

    private var valid: (internalWatts: Double, chipWatts: Double)? {
        guard let internalWatts, let chipWatts,
              internalWatts.isFinite, chipWatts.isFinite,
              internalWatts > 0, chipWatts >= 0,
              chipWatts <= internalWatts else { return nil }
        return (internalWatts, chipWatts)
    }

    var otherWatts: Double? {
        valid.map { $0.internalWatts - $0.chipWatts }
    }

    var chipFraction: Double? {
        valid.map { $0.chipWatts / $0.internalWatts }
    }

    var otherFraction: Double? {
        chipFraction.map { 1 - $0 }
    }
}

/// Choose topology from hardware state, never from a model-name string.
enum PowerSourceMode: Equatable {
    case desktop
    case battery
    case adapter
    case adapterCharging
    case adapterAssisted

    init(reading: ChipBarPowerReading) {
        guard reading.hasBattery else { self = .desktop; return }
        guard reading.onAdapter else { self = .battery; return }
        if reading.isCharging, (reading.batteryWatts ?? 0) > 0.5 {
            self = .adapterCharging
        } else if (reading.batteryWatts ?? 0) < -0.5 {
            self = .adapterAssisted
        } else {
            self = .adapter
        }
    }

    var showsBatteryBranch: Bool {
        self == .adapterCharging || self == .adapterAssisted
    }
}

private struct PowerTile: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(12)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 13))
    }
}

private struct EnergyNode: View {
    let name: String
    let watts: Double?
    let amber: Bool
    var highlighted = false

    private let glow = Color(red: 0.93, green: 0.62, blue: 0.27)

    var body: some View {
        VStack(spacing: 5) {
            Text(name)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(watts.map { String(format: "%.1f", $0) } ?? "—")
                .font(.system(size: highlighted ? 17 : 12,
                              weight: .semibold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.75)
                .lineLimit(1)
            Text("W").font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .frame(width: highlighted ? 86 : 61, height: highlighted ? 100 : 47)
        .background(Color.primary.opacity(0.035),
                    in: RoundedRectangle(cornerRadius: 11))
        .overlay {
            RoundedRectangle(cornerRadius: 11)
                .strokeBorder(amber ? glow.opacity(0.85) : Color.primary.opacity(0.10),
                              lineWidth: amber ? 1.4 : 0.6)
        }
        .shadow(color: amber ? glow.opacity(0.19) : .clear,
                radius: highlighted ? 10 : 0)
        .opacity(watts == nil && !highlighted ? 0.42 : 1)
        .accessibilityElement(children: .combine)
    }
}

private struct PowerDash: View {
    var amber: Bool
    var body: some View {
        HStack(spacing: 1) {
            Path { path in
                path.move(to: CGPoint(x: 0, y: 4))
                path.addLine(to: CGPoint(x: 14, y: 4))
            }
            .stroke(amber ? Color.orange.opacity(0.9) : Color.secondary.opacity(0.48),
                    style: StrokeStyle(lineWidth: 1.4, dash: [3, 3]))
            .frame(width: 14, height: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 6, weight: .semibold))
                .foregroundStyle(amber ? Color.orange : Color.secondary)
        }
        .frame(width: 19, height: 10)
        .accessibilityHidden(true)
    }
}

struct PowerSupplyDetailView: View {
    @ObservedObject var monitor: Monitor
    let active: Bool
    let close: () -> Void
    @ObservedObject private var sampler = ChipBarPowerFlowModel.shared

    private let amber = Color(red: 0.93, green: 0.62, blue: 0.27)
    private var reading: ChipBarPowerReading { sampler.reading }
    private var breakdown: PowerDistribution {
        PowerDistribution(internalWatts: reading.systemWatts,
                          chipWatts: monitor.connected ? monitor.sample?.total : nil)
    }
    private var mode: PowerSourceMode { PowerSourceMode(reading: reading) }
    private var inputWatts: Double? {
        guard reading.hasBattery, reading.onAdapter else { return nil }
        return reading.adapterWatts
    }
    private var batteryOutputWatts: Double? {
        guard let watts = reading.batteryWatts, watts.isFinite, watts < 0 else { return nil }
        return abs(watts)
    }
    private var chargingWatts: Double? {
        guard mode == .adapterCharging,
              let watts = reading.batteryWatts, watts.isFinite, watts >= 0 else { return nil }
        return watts
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) {
                Button(action: close) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 26, height: 29)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 9))
                }
                .accessibilityLabel("返回主页面")
                VStack(alignment: .leading, spacing: 2) {
                    Text("电源与功率").font(.headline)
                    Text(reading.live ? "传感器在线 · 每秒采样" : "等待传感器 · 每秒采样")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text(reading.live ? "实时" : "离线")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(reading.live ? Color.green : Color.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background((reading.live ? Color.green : Color.secondary).opacity(0.11),
                                in: Capsule())
            }
            .frame(height: 40)

            VStack(alignment: .leading, spacing: 10) {
                Text("能量流向").font(.caption.weight(.semibold))
                HStack(alignment: .center, spacing: 3) {
                    if mode != .desktop {
                        VStack(spacing: 5) {
                            if mode == .battery {
                                EnergyNode(name: "电池供电", watts: batteryOutputWatts,
                                           amber: false)
                            } else {
                                EnergyNode(name: "外部供电", watts: inputWatts,
                                           amber: false)
                            }
                            if mode.showsBatteryBranch {
                                PowerDash(amber: false)
                                    .rotationEffect(.degrees(mode == .adapterCharging ? 90 : -90))
                                    .frame(height: 17)
                                EnergyNode(
                                    name: mode == .adapterCharging ? "电池充电" : "电池补充",
                                    watts: mode == .adapterCharging
                                        ? chargingWatts : batteryOutputWatts,
                                    amber: false
                                )
                            }
                        }
                        PowerDash(amber: false)
                    }
                    EnergyNode(name: "内部功率", watts: reading.systemWatts,
                               amber: true, highlighted: true)
                    PowerDash(amber: true)
                    VStack(spacing: 6) {
                        EnergyNode(name: "芯片", watts: breakdown.chipWatts, amber: false)
                        EnergyNode(name: "其余部件", watts: breakdown.otherWatts, amber: false)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: mode.showsBatteryBranch ? 128 : 112)
            }
            .modifier(PowerTile())

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("内部功率构成").font(.caption.weight(.semibold))
                    Spacer(minLength: 0)
                    Circle().fill(amber).frame(width: 6, height: 6)
                    Text("芯片")
                    Circle().fill(Color.white.opacity(0.3)).frame(width: 6, height: 6)
                    Text("其余部件")
                }
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.30))
                        if let fraction = breakdown.chipFraction {
                            Capsule().fill(amber)
                                .frame(width: geo.size.width * fraction)
                        }
                    }
                }
                .frame(height: 8)
            }
            .modifier(PowerTile())

            VStack(spacing: 7) {
                readout("数据源", reading.sourceKey.map { "SMC \($0)" } ?? "—")
                Divider().opacity(0.25)
                readout("采样间隔", "每秒")
                Divider().opacity(0.25)
                HStack {
                    Text("传感器状态").foregroundStyle(.secondary)
                    Spacer()
                    Circle().fill(reading.live ? Color.green : Color.secondary)
                        .frame(width: 6, height: 6)
                    Text(reading.live ? "在线" : "离线")
                }
            }
            .font(.system(size: 11))
            .modifier(PowerTile())

        }
        .help("内部 DC 功率不是插座 AC 输入功耗。其余部件为内部功率减去芯片总功率的估算值。")
    }

    private func readout(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
    }

}
