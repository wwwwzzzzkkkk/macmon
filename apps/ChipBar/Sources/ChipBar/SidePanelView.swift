import SwiftUI

enum DashboardSidePanelKind: String, Equatable {
    case applications
    case power
}

/// One source of truth for sidebar geometry, including the placeholder's
/// first frame. The window never reads a stale @Published kind.
enum SidePanelLayout {
    static let width: CGFloat = 314
    static let padding: CGFloat = 12
    static let contentWidth: CGFloat = width - 2 * padding
    static let applicationHeight: CGFloat = 248

    static func powerHeight(hasBattery: Bool, charging: Bool) -> CGFloat {
        guard hasBattery else { return 188 }
        return charging ? 312 : 282
    }

    static func height(for kind: DashboardSidePanelKind) -> CGFloat {
        switch kind {
        case .applications: return applicationHeight
        case .power: return powerHeight(hasBattery: false, charging: false)
        }
    }
}

/// Lightweight first frame. The placeholder uses exactly the same top inset
/// as the mounted content and never reserves a giant invisible bottom region.
struct SidePanelLoadingView: View {
    let kind: DashboardSidePanelKind

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(kind == .power ? "电源与功率" : "应用占用",
                  systemImage: kind == .power ? "bolt.horizontal.circle" : "square.stack.3d.up")
                .font(.headline)
                .frame(height: 28)
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(0.045))
                .frame(height: kind == .power ? 95 : 165)
                .overlay {
                    ProgressView().controlSize(.small)
                        .accessibilityLabel("正在准备数据")
                }
        }
        .frame(width: SidePanelLayout.contentWidth, alignment: .topLeading)
        .padding(SidePanelLayout.padding)
    }
}

/// The parent dashboard stays stationary. Only this independently hosted
/// native glass NSPanel changes height as power source information arrives.
struct DashboardSidePanelView: View {
    @ObservedObject var monitor: Monitor
    @ObservedObject var state: DashboardState
    var close: () -> Void
    var onPowerLayoutChange: (Bool, Bool) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: state.sidePanel == .power
                      ? "bolt.horizontal.circle" : "square.stack.3d.up")
                    .foregroundStyle(Color(red: 0.22, green: 0.65, blue: 0.79))
                Text(state.sidePanel == .power ? "电源与功率" : "应用占用")
                    .font(.headline)
                Spacer(minLength: 0)
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("关闭侧边卡片")
                .buttonStyle(ChipBarPressStyle())
            }
            .frame(height: 28)

            if state.sidePanel == .applications {
                ApplicationUsageSection(monitor: monitor, state: state, showsDisclosure: false)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(x: 8)))
            } else if state.sidePanel == .power {
                ChipBarPowerFlowView(active: !monitor.paused && !monitor.sleeping,
                                     onLayoutMode: onPowerLayoutChange)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(x: 8)))
            }
        }
        .frame(width: SidePanelLayout.contentWidth, alignment: .topLeading)
        .padding(SidePanelLayout.padding)
        .buttonStyle(ChipBarPressStyle())
    }
}

/// The fine energy line animates only while live; the SMC sampler runs at its
/// own cadence, independent from the decorative Canvas timeline.
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
                let from = CGPoint(x: 84, y: startY)
                let to = CGPoint(x: size.width - 84, y: endY)
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
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(tint)
                .frame(height: 18)
            Text(watts.map { String(format: "%.1f W", $0) } ?? "—")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 84, height: 66)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(tint.opacity(0.14), lineWidth: 0.75)
        }
        .accessibilityElement(children: .combine)
    }
}

struct ChipBarPowerFlowView: View {
    var active: Bool
    var onLayoutMode: (Bool, Bool) -> Void
    @StateObject private var model = ChipBarPowerFlowModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let cyan = Color(red: 0.22, green: 0.65, blue: 0.79)
    private let green = Color(red: 0.25, green: 0.68, blue: 0.53)

    private var power: ChipBarPowerReading { model.reading }
    private var charging: Bool {
        power.hasBattery && power.onAdapter && (power.batteryWatts ?? 0) > 0.5
    }
    private var discharging: Bool { power.hasBattery && !power.onAdapter }
    private var hasSystemPower: Bool { power.live && (power.systemWatts ?? 0) > 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(power.hasBattery
                         ? (power.onAdapter ? "适配器供电" : "电池供电")
                         : "内部功率")
                        .font(.subheadline.weight(.semibold))
                    Text(power.live ? "实时" : "读取中")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if let percent = power.batteryPercent {
                    Text(String(format: "%.0f%%", percent))
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                } else {
                    Image(systemName: power.hasBattery ? "battery.75percent" : "bolt.circle")
                        .font(.title3)
                        .foregroundStyle(cyan)
                }
            }
            .frame(height: 34)

            if !power.hasBattery {
                // Desktop Macs report a single internal rail. Do not invent
                // an external AC source or waste space on a fake flow diagram.
                VStack(spacing: 6) {
                    Text(power.systemWatts.map { String(format: "%.1f W", $0) } ?? "— W")
                        .font(.system(size: 27, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(power.live ? Color.primary : Color.secondary)
                    Text("系统内部功率")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 86)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
            } else {
                if let percent = power.batteryPercent {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.08))
                            Capsule().fill(green.opacity(0.80))
                                .frame(width: geometry.size.width *
                                       CGFloat(min(100, max(0, percent)) / 100))
                        }
                    }
                    .frame(height: 6)
                    .accessibilityLabel("电池电量 \(Int(percent.rounded()))%")
                }
                HStack(spacing: 8) {
                    Text("能量流向").font(.caption.weight(.semibold))
                    Spacer()
                    Circle().fill(power.live ? green : Color.secondary)
                        .frame(width: 5, height: 5)
                    Text(power.live ? "实时" : "未连接")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .frame(height: 16)

                GeometryReader { geo in
                    ZStack {
                        if charging {
                            PowerFlowEnergyTrack(startY: 85, endY: 42,
                                                 tint: cyan, energized: hasSystemPower,
                                                 active: active, reduceMotion: reduceMotion)
                            PowerFlowEnergyTrack(startY: 85, endY: 130,
                                                 tint: green, energized: power.live &&
                                                     (power.batteryWatts ?? 0) > 0,
                                                 active: active, reduceMotion: reduceMotion)
                        } else {
                            PowerFlowEnergyTrack(startY: 71, endY: 71,
                                                 tint: cyan, energized: hasSystemPower,
                                                 active: active, reduceMotion: reduceMotion)
                        }
                        if discharging {
                            PowerFlowNode(title: "电池输出",
                                          watts: power.batteryWatts.map(abs),
                                          symbol: "battery.75percent", tint: green)
                                .position(x: 42, y: 71)
                            PowerFlowNode(title: "系统负载", watts: power.systemWatts,
                                          symbol: "laptopcomputer")
                                .position(x: geo.size.width - 42, y: 71)
                        } else {
                            PowerFlowNode(title: "适配器输入", watts: power.adapterWatts,
                                          symbol: "powerplug")
                                .position(x: 42, y: charging ? 85 : 71)
                            PowerFlowNode(title: "系统负载", watts: power.systemWatts,
                                          symbol: "laptopcomputer")
                                .position(x: geo.size.width - 42,
                                          y: charging ? 42 : 71)
                            if charging {
                                PowerFlowNode(title: "电池充电", watts: power.batteryWatts,
                                              symbol: "battery.75percent", tint: green)
                                    .position(x: geo.size.width - 42, y: 130)
                            }
                        }
                    }
                }
                .frame(height: charging ? 172 : 142)
                .background(Color.primary.opacity(0.035),
                            in: RoundedRectangle(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.primary.opacity(0.055), lineWidth: 0.7)
                }
            }
        }
        // Hide implementation details from the compact UI. They are still
        // discoverable and remain available to VoiceOver.
        .help(power.sourceLabel + " · " + (power.hasBattery
              ? "系统侧功率为估算值，不代表插座 AC 功耗。"
              : "仅内部 DC 读数，非插座 AC 功耗。"))
        .accessibilityHint(power.sourceLabel)
        .onAppear { onLayoutMode(power.hasBattery, charging) }
        .onChange(of: power.hasBattery) { _ in onLayoutMode(power.hasBattery, charging) }
        .onChange(of: charging) { _ in onLayoutMode(power.hasBattery, charging) }
        .task(id: active) {
            guard active else { return }
            await model.watch()
        }
    }
}
