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

/// A restrained flowing-current path. Canvas draws at 18 fps only while the
/// sidecard is visible, powered and Reduce Motion is off. Data is still polled
/// by the SMC actor independently, once per second.
private struct PowerFlowEnergyTrack: View {
    let startY: CGFloat
    let endY: CGFloat
    let tint: Color
    let energized: Bool
    let active: Bool
    let reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 18.0,
                                paused: !energized || !active || reduceMotion)) { timeline in
            Canvas { context, size in
                let from = CGPoint(x: 92, y: startY)
                let to = CGPoint(x: size.width - 92, y: endY)
                let midX = (from.x + to.x) / 2
                let controlA = CGPoint(x: midX, y: from.y)
                let controlB = CGPoint(x: midX, y: to.y)
                var line = Path()
                line.move(to: from)
                line.addCurve(to: to, control1: controlA, control2: controlB)
                context.stroke(line, with: .color(tint.opacity(0.16)),
                               style: StrokeStyle(lineWidth: 5.5, lineCap: .round))
                if energized {
                    context.stroke(line, with: .color(tint.opacity(0.68)),
                                   style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    if !reduceMotion {
                        let phase = timeline.date.timeIntervalSinceReferenceDate * 0.27
                        for index in 0..<4 {
                            let t = CGFloat((phase + Double(index) * 0.25)
                                .truncatingRemainder(dividingBy: 1))
                            let u: CGFloat = 1 - t
                            let x = u*u*u*from.x + 3*u*u*t*controlA.x
                                + 3*u*t*t*controlB.x + t*t*t*to.x
                            let y = u*u*u*from.y + 3*u*u*t*controlA.y
                                + 3*u*t*t*controlB.y + t*t*t*to.y
                            let dot = CGRect(x: x - 2.8, y: y - 2.8,
                                             width: 5.6, height: 5.6)
                            context.fill(Path(ellipseIn: dot),
                                         with: .color(tint.opacity(0.95)))
                        }
                    }
                }
            }
        }
    }
}

private struct PowerFlowNode: View {
    let title: String
    let watts: Double?
    let symbol: String
    var tint = Color(red: 0.22, green: 0.65, blue: 0.79)

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(tint)
                .frame(height: 19)
            Text(watts.map { String(format: "%.1f W", $0) } ?? "—")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 91, height: 72)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 13))
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .strokeBorder(tint.opacity(0.14), lineWidth: 0.75)
        }
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
    private var charging: Bool {
        power.hasBattery && power.onAdapter &&
        (power.batteryWatts ?? 0) > 0.5
    }
    private var discharging: Bool { power.hasBattery && !power.onAdapter }
    private var hasSystemPower: Bool { power.live && (power.systemWatts ?? 0) > 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(power.hasBattery
                         ? (power.onAdapter ? "适配器供电" : "电池供电")
                         : "内部电源轨")
                        .font(.subheadline.weight(.semibold))
                    Text(power.live ? "传感器在线 · 每秒采样" : "等待 SMC 传感器")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 3)
                if let percent = power.batteryPercent {
                    Text(String(format: "%.0f%%", percent))
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                } else {
                    Image(systemName: "bolt.circle")
                        .font(.title3)
                        .foregroundStyle(cyan)
                }
            }
            if let percent = power.batteryPercent {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08))
                        Capsule().fill(green.opacity(0.80))
                            .frame(width: geometry.size.width *
                                   CGFloat(min(100, max(0, percent)) / 100))
                    }
                }
                .frame(height: 5)
                .accessibilityLabel("电池电量 \(Int(percent.rounded()))%")
            }

            HStack(spacing: 8) {
                Text("能量流向")
                    .font(.caption.weight(.semibold))
                Spacer()
                Circle().fill(power.live ? green : Color.secondary)
                    .frame(width: 5, height: 5)
                Text(power.live ? "实时" : "暂无数据")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geo in
                ZStack {
                    if charging {
                        PowerFlowEnergyTrack(startY: 98, endY: 48,
                                             tint: cyan, energized: hasSystemPower,
                                             active: active, reduceMotion: reduceMotion)
                        PowerFlowEnergyTrack(startY: 98, endY: 148,
                                             tint: green,
                                             energized: power.live && (power.batteryWatts ?? 0) > 0,
                                             active: active, reduceMotion: reduceMotion)
                    } else {
                        PowerFlowEnergyTrack(startY: 98, endY: 98,
                                             tint: cyan, energized: hasSystemPower,
                                             active: active, reduceMotion: reduceMotion)
                    }
                    if discharging {
                        PowerFlowNode(title: "电池输出", watts: power.batteryWatts.map(abs),
                                      symbol: "battery.75percent", tint: green)
                            .position(x: 47, y: 98)
                        PowerFlowNode(title: "系统负载", watts: power.systemWatts,
                                      symbol: "laptopcomputer")
                            .position(x: geo.size.width - 47, y: 98)
                    } else if power.hasBattery {
                        PowerFlowNode(title: "适配器输入", watts: power.adapterWatts,
                                      symbol: "powerplug")
                            .position(x: 47, y: 98)
                        PowerFlowNode(title: "系统负载", watts: power.systemWatts,
                                      symbol: "laptopcomputer")
                            .position(x: geo.size.width - 47, y: charging ? 48 : 98)
                        if charging {
                            PowerFlowNode(title: "电池充电", watts: power.batteryWatts,
                                          symbol: "battery.75percent", tint: green)
                                .position(x: geo.size.width - 47, y: 148)
                        }
                    } else {
                        PowerFlowNode(title: "外部供电", watts: nil,
                                      symbol: "powerplug")
                            .position(x: 47, y: 98)
                        PowerFlowNode(title: "内部功率", watts: power.systemWatts,
                                      symbol: "desktopcomputer")
                            .position(x: geo.size.width - 47, y: 98)
                    }
                }
            }
            .frame(height: 196)
            .background(Color.primary.opacity(0.035),
                        in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.primary.opacity(0.055), lineWidth: 0.7)
            }

            Text(power.sourceLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(power.hasBattery
                 ? "系统功率为适配器与电池读数的差值估算；非插座功耗。"
                 : "SMC 为内部 DC 功率读数，并非墙插 AC 功耗。")
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
