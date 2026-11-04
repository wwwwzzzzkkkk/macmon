import SwiftUI

enum DashboardSidePanelKind: String, Equatable {
    case applications
    case power
}

/// Lightweight first frame avoids synchronously constructing application/SMC views.
struct SidePanelLoadingView: View {
    let kind: DashboardSidePanelKind
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Label(kind == .power ? "电源与功率" : "应用占用",
                  systemImage: kind == .power ? "bolt.horizontal.circle" : "square.stack.3d.up")
                .font(.headline)
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(0.045))
                .frame(height: kind == .power ? 210 : 180)
                .overlay {
                    ProgressView().controlSize(.small).accessibilityLabel("正在准备数据")
                }
            Spacer(minLength: 0)
        }
        .frame(width: 308, height: kind == .power ? 402 : 296, alignment: .topLeading)
        .padding(13)
    }
}

/// Hosted in a separate nonactivating NSPanel; the main dashboard never resizes
/// when switching the resource ranking or updating the power flow.
struct DashboardSidePanelView: View {
    @ObservedObject var monitor: Monitor
    @ObservedObject var state: DashboardState
    var close: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: state.sidePanel == .power ? "bolt.horizontal.circle" : "square.stack.3d.up")
                    .foregroundStyle(Color(red: 0.22, green: 0.65, blue: 0.79))
                Text(state.sidePanel == .power ? "电源与功率" : "应用占用")
                    .font(.headline)
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("收起侧边卡片")
                .buttonStyle(ChipBarPressStyle())
            }
            .frame(height: 28)

            ZStack(alignment: .topLeading) {
                if state.sidePanel == .applications {
                    ApplicationUsageSection(monitor: monitor, state: state, showsDisclosure: false)
                        .transition(reduceMotion ? .opacity :
                            .asymmetric(insertion: .offset(x: 12).combined(with: .opacity),
                                        removal: .offset(x: -10).combined(with: .opacity)))
                } else if state.sidePanel == .power {
                    ChipBarPowerFlowView(active: !monitor.paused && !monitor.sleeping)
                        .transition(reduceMotion ? .opacity :
                            .asymmetric(insertion: .offset(x: 12).combined(with: .opacity),
                                        removal: .offset(x: -10).combined(with: .opacity)))
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.23), value: state.sidePanel)
        }
        .frame(width: 308, height: state.sidePanel == .power ? 402 : 296, alignment: .topLeading)
        .padding(13)
        .buttonStyle(ChipBarPressStyle())
    }
}

private struct PowerFlowBand: Shape {
    var fromY: CGFloat
    var toY: CGFloat
    var thickness: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(toY, thickness) }
        set { toY = newValue.first; thickness = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let x0: CGFloat = 48
        let x1: CGFloat = rect.width - 48
        let mid = (x0 + x1) / 2
        let t = max(3, thickness) / 2
        var path = Path()
        path.move(to: CGPoint(x: x0, y: fromY - t))
        path.addCurve(to: CGPoint(x: x1, y: toY - t),
                      control1: CGPoint(x: mid, y: fromY - t),
                      control2: CGPoint(x: mid, y: toY - t))
        path.addLine(to: CGPoint(x: x1, y: toY + t))
        path.addCurve(to: CGPoint(x: x0, y: fromY + t),
                      control1: CGPoint(x: mid, y: toY + t),
                      control2: CGPoint(x: mid, y: fromY + t))
        path.closeSubpath()
        return path
    }
}

private struct PowerFlowNode: View {
    let title: String
    let watts: Double?
    let symbol: String
    var batteryPercent: Double? = nil

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 18))
                .foregroundStyle(Color(red: 0.28, green: 0.69, blue: 0.82))
            Text(watts.map { String(format: "%.1f W", $0) } ?? "— W")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 90, height: 75)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

struct ChipBarPowerFlowView: View {
    var active: Bool
    @StateObject private var model = ChipBarPowerFlowModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let cyan = Color(red: 0.22, green: 0.65, blue: 0.79)
    private let green = Color(red: 0.25, green: 0.68, blue: 0.53)

    private var power: ChipBarPowerReading { model.reading }
    private var batteryCharging: Bool { power.hasBattery && power.onAdapter && (power.batteryWatts ?? 0) > 0.5 }
    private var batteryDischarging: Bool { power.hasBattery && !power.onAdapter }

    private func width(for watts: Double?) -> CGFloat {
        guard let watts, watts.isFinite, watts > 0 else { return 3 }
        let reference = max(1, power.adapterWatts ?? power.systemWatts ?? watts)
        return CGFloat(min(44, max(4, watts / reference * 44)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(power.hasBattery ? (power.onAdapter ? "连接充电器" : "使用电池") : "台式 Mac 电源",
                      systemImage: power.hasBattery ? "battery.75percent" : "powerplug")
                    .font(.subheadline.weight(.medium))
                Spacer()
                if let percent = power.batteryPercent {
                    Text(String(format: "%.0f%%", percent))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }
            }
            if let percent = power.batteryPercent {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.17))
                        Capsule().fill(green.opacity(0.85))
                            .frame(width: geometry.size.width * CGFloat(percent / 100))
                    }
                }
                .frame(height: 6)
                .accessibilityLabel("电池电量 \(Int(percent.rounded()))%")
            }

            HStack {
                Text("功率流向")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("实时 · SMC")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geo in
                ZStack {
                    if batteryCharging {
                        PowerFlowBand(fromY: 103, toY: 54, thickness: width(for: power.systemWatts))
                            .fill(cyan.opacity(0.50))
                        PowerFlowBand(fromY: 114, toY: 161, thickness: width(for: power.batteryWatts))
                            .fill(green.opacity(0.48))
                    } else {
                        PowerFlowBand(fromY: 105, toY: 105, thickness: width(for: power.systemWatts))
                            .fill(cyan.opacity(power.live ? 0.55 : 0.15))
                    }
                    if batteryDischarging {
                        PowerFlowNode(title: "电池放电", watts: power.batteryWatts.map(abs),
                                      symbol: "battery.75percent")
                            .position(x: 45, y: 105)
                        PowerFlowNode(title: "系统负载", watts: power.systemWatts,
                                      symbol: "laptopcomputer")
                            .position(x: geo.size.width - 45, y: 105)
                    } else if power.hasBattery {
                        PowerFlowNode(title: "适配器输入", watts: power.adapterWatts,
                                      symbol: "powerplug")
                            .position(x: 45, y: 105)
                        PowerFlowNode(title: "系统侧估算", watts: power.systemWatts,
                                      symbol: "laptopcomputer")
                            .position(x: geo.size.width - 45, y: batteryCharging ? 54 : 105)
                        if batteryCharging {
                            PowerFlowNode(title: "电池充电", watts: power.batteryWatts,
                                          symbol: "battery.75percent")
                                .position(x: geo.size.width - 45, y: 161)
                        }
                    } else {
                        PowerFlowNode(title: "AC 供电", watts: nil, symbol: "powerplug")
                            .position(x: 45, y: 105)
                        PowerFlowNode(title: "内部系统功率", watts: power.systemWatts, symbol: "desktopcomputer")
                            .position(x: geo.size.width - 45, y: 105)
                    }
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.32), value: power)
            }
            .frame(height: 210)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 13))

            Text(power.sourceLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(power.hasBattery
                 ? "电池正值代表充电，负值代表放电。系统侧功率通过输入与电池功率的差值估算。"
                 : "SMC 反映电脑内部电源轨，不等于插座端的交流输入功率。")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task(id: active) {
            guard active else { return }
            await model.watch()
        }
    }
}
