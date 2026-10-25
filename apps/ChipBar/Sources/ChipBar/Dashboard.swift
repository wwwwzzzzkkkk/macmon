import SwiftUI
import QuartzCore
import ChipBarCore

enum DashboardLayout {
    static let width: CGFloat = 370
}

enum DashboardMotion {
    static let duration = 0.20
    static let navigation = 0.24
    // The page slide finishes before the glass window settles to its new size.
    static let navigationResize = 0.34
    static let navigationSpringCurve = CAMediaTimingFunction(controlPoints: 0.20, 0.90, 0.30, 1.03)
    static let popoverEnter = 0.18
    static let popoverExit = 0.14
    static let popoverCurve = CAMediaTimingFunction(name: .easeInEaseOut)
}

final class DashboardState: ObservableObject {
    @Published var chartMetric: PowerMetric = .total
    @Published var showSettings = false
    @Published var showApplications = CommandLine.arguments.contains("--apps")
    @Published var applicationsExpansion = CommandLine.arguments.contains("--apps") ? 1.0 : 0.0
    @Published var showSSDDetails = CommandLine.arguments.contains("--ssd-details")
    @Published var showSystemDetails = CommandLine.arguments.contains("--system-details")
        || CommandLine.arguments.contains("--ssd-details")
        || CommandLine.arguments.contains("--ssd-disclosure-only")
    @Published var ssdExpansion = CommandLine.arguments.contains("--ssd-details") ? 1.0 : 0.0
    @Published var ssdDetailsHeight: CGFloat = 0
    @Published var applicationMetric: ApplicationResource = CommandLine.arguments.contains("--apps-gpu") ? .gpu : CommandLine.arguments.contains("--apps-ane") ? .ane : .cpu
    init(showSettings: Bool = false) {
        self.showSettings = showSettings
    }
    /// Every menu-bar open starts from the same visual state. Saved user
    /// preferences (refresh interval, menu items and SSD monitoring) remain.
    /// Dedicated -- QA flags are preserved for screenshot/interaction tests.
    func resetForOpening(arguments: [String] = CommandLine.arguments) {
        let apps = arguments.contains("--apps")
        let ssd = arguments.contains("--ssd-details")
        let system = arguments.contains("--system-details") || ssd
            || arguments.contains("--ssd-disclosure-only")
        chartMetric = .total
        showSettings = false
        showApplications = apps
        applicationsExpansion = apps ? 1 : 0
        showSSDDetails = ssd
        ssdExpansion = ssd ? 1 : 0
        showSystemDetails = system
        ssdDetailsHeight = 0
        applicationMetric = arguments.contains("--apps-gpu") ? .gpu :
            arguments.contains("--apps-ane") ? .ane : .cpu
    }
    func toggleApplications() { showApplications.toggle() }
    func toggleSettings() { showSettings.toggle() }
}

struct Dashboard: View {
    @ObservedObject var monitor: Monitor
    @StateObject private var state: DashboardState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let accent = Color(red: 0.22, green: 0.65, blue: 0.79)
    private let appIcon = Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
        .flatMap { NSImage(contentsOf: $0) }

    init(monitor: Monitor, showSettings: Bool = false, state: DashboardState? = nil) {
        self.monitor = monitor
        _state = StateObject(wrappedValue: state ?? DashboardState(showSettings: showSettings))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if state.showSettings {
                settingsScreen
                    .transition(reduceMotion ? .opacity :
                        .asymmetric(
                            insertion: .offset(x: 18).combined(with: .opacity),
                            removal: .offset(x: 18).combined(with: .opacity)))
            } else {
                monitoringScreen
                    .transition(reduceMotion ? .opacity :
                        .asymmetric(
                            insertion: .offset(x: -18).combined(with: .opacity),
                            removal: .offset(x: -18).combined(with: .opacity)))
            }
        }
        // Constrain the *content* rather than only its padded outer frame.
        // Otherwise intrinsic widths (e.g. segmented picker) can run under
        // the scroller and clip the right-hand side of the glass popover.
        .frame(width: DashboardLayout.width - 30, alignment: .topLeading)
        .padding(.horizontal, 15)
        .padding(.vertical, 14)
        .frame(width: DashboardLayout.width, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .buttonStyle(ChipBarPressStyle())
        .animation(ChipBarMotion.optional(ChipBarMotion.navigation, reduceMotion: reduceMotion),
                   value: state.showSettings)
    }

    private var monitoringScreen: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            hero
            powerCards
            utilizationOverview
            ApplicationUsageSection(monitor: monitor, state: state)
            trend
            systemMemory
            ChipBarSectionToggle(title: "系统详情", systemImage: "square.stack.3d.up",
                                 expanded: state.showSystemDetails) {
                // Animate the chevron and NSPanel height, but do not animate
                // SwiftUI's intrinsic document height at the same time.
                // Competing layout springs previously shifted the full view.
                withTransaction(Transaction(animation: nil)) {
                    state.showSystemDetails.toggle()
                }
            }
            if state.showSystemDetails {
                VStack(alignment: .leading, spacing: 9) {
                    InternalStorageSection()
                    fanOverview
                    SSDSection(ssd: monitor.ssd, state: state)
                }
                // Keep content in its final position; the glass viewport
                // handles expansion. No top-offset transition / vertical hop.
                .transition(.opacity)
            }
            errorPanel
            Text(monitor.status).font(.caption).foregroundStyle(.secondary)
            footer
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var settingsScreen: some View {
        VStack(alignment: .leading, spacing: 12) {
            settingsNavigation
            settingsPanel
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var settingsNavigation: some View {
        HStack(spacing: 10) {
            Button {
                state.showSettings = false
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left").font(.caption.weight(.semibold))
                    Text("返回").font(.subheadline)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(ChipBarPressStyle())
            .accessibilityLabel("返回监控面板")

            Spacer()
            Text("设置").font(.headline)
            Spacer()
            Image(systemName: "gearshape")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var header: some View {
            HStack(spacing: 10) {
                if let appIcon {
                    Image(nsImage: appIcon).resizable().interpolation(.high)
                        .frame(width: 28, height: 28).accessibilityHidden(true)
                } else {
                    Image(systemName: "waveform.path.ecg")
                        .font(.title2).foregroundStyle(accent)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("ChipBar").font(.headline)
                    Text(monitor.sample?.chip ?? monitor.hardware)
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.tail)
                }
                Spacer()
                Circle().fill(monitor.connected ? Color.green : Color.orange).frame(width: 6, height: 6)
                Text(monitor.paused ? "已暂停" : monitor.connected ? "实时" : "等待数据")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }

    }

    @ViewBuilder private var hero: some View {
            VStack(alignment: .leading, spacing: 6) {
                Text("芯片合计功率").font(.subheadline).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    AnimatedMetricValue(value: monitor.connected ? monitor.sample?.total : nil, decimals: 1)
                        .font(.system(size: 36, weight: .medium, design: .rounded)).monospacedDigit()
                    Text("W").font(.title3).foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "bolt.fill").font(.title).foregroundStyle(accent.opacity(0.6))
                }
                Text("CPU + GPU + ANE · 非整机插座输入功率")
                    .font(.caption).foregroundStyle(.secondary)
            }

    }

    @ViewBuilder private var powerCards: some View {
        HStack(spacing: 8) {
            PowerMetricCard(title: "CPU", power: monitor.sample?.cpu,
                            connected: monitor.connected, icon: "cpu",
                            temperature: monitor.sample?.cpuTemperature, showsTemperature: true)
            PowerMetricCard(title: "GPU", power: monitor.sample?.gpu,
                            connected: monitor.connected, icon: "square.stack.3d.up",
                            temperature: monitor.sample?.gpuTemperature, showsTemperature: true)
            PowerMetricCard(title: "ANE", power: monitor.sample?.ane,
                            connected: monitor.connected, icon: "sparkles")
        }
    }

    /// Percentage-based rings, unlike power values which have no universal
    /// 100% wattage. One restrained accent family preserves Liquid Glass contrast.
    private var utilizationOverview: some View {
        HStack(spacing: 8) {
            MetricRing(title: "CPU 占用", percentage: monitor.connected ? monitor.sample?.cpuUtilization : nil,
                       tint: accent)
            MetricRing(title: "GPU 占用", percentage: monitor.connected ? monitor.sample?.gpuUtilization : nil,
                       tint: accent.opacity(0.78))
            MetricRing(title: "内存", percentage: monitor.connected ? monitor.sample?.memory?.usedPercent : nil,
                       tint: accent.opacity(0.60))
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 7)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder private var trend: some View {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("功率趋势").font(.subheadline.weight(.medium))
                    Spacer()
                    Picker("趋势指标", selection: $state.chartMetric) {
                        ForEach(PowerMetric.allCases) { Text($0.title).tag($0) }
                    }.labelsHidden().pickerStyle(.menu).fixedSize()
                        .animation(ChipBarMotion.optional(ChipBarMotion.selection,
                                                        reduceMotion: reduceMotion),
                                   value: state.chartMetric)
                }
                if monitor.history.compactMap({ $0.power(state.chartMetric) }).isEmpty {
                    Text("等待有效采样后显示趋势")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).frame(height: 95)
                } else {
                    PowerTrendPlot(points: chartPoints,
                        maximum: max(1, (monitor.history.compactMap { $0.power(state.chartMetric) }.max() ?? 1) * 1.15),
                        axisDates: trendAxisDates, dateFormat: trendDateFormat, accent: accent)
                    .frame(height: 95)
                    .id(state.chartMetric)
                    .transition(.opacity)
                    .animation(ChipBarMotion.optional(ChipBarMotion.selection,
                                                      reduceMotion: reduceMotion),
                               value: state.chartMetric)
                }
                HStack {
                    Text("最近 10 分钟 · W")
                    Spacer()
                    Text("均值 \(value(average)) W")
                }.font(.caption2).foregroundStyle(.secondary)
            }

    }

    @ViewBuilder private var systemMemory: some View {
        HStack {
            Label("内存", systemImage: "memorychip")
            Spacer(minLength: 8)
            if let memory = monitor.connected ? monitor.sample?.memory : nil {
                Text(String(format: "%.1f / %.1f GB · %.0f%%", memory.usedGiB, memory.totalGiB, memory.usedPercent))
                    .lineLimit(1).minimumScaleFactor(0.85)
            } else {
                Text("不可用").foregroundStyle(.secondary)
            }
            MemoryPressureBadge(level: monitor.memoryPressure)
        }
        .font(.subheadline).monospacedDigit()
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var errorPanel: some View {
            if let error = monitor.error {
                VStack(alignment: .leading, spacing: 5) {
                    Label("采样需要处理", systemImage: "exclamationmark.triangle").font(.caption.weight(.semibold))
                    Text(error).font(.caption).textSelection(.enabled).lineLimit(5)
                    Button("立即重试") { monitor.restart() }.font(.caption)
                }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            }

    }

    private var fanOverview: some View {
        HStack(spacing: 9) {
            Label("风扇", systemImage: "fanblades")
            Spacer()
            let fans = monitor.connected ? monitor.sample?.fans ?? [] : []
            Text(fans.isEmpty ? "不可用" : fans.map { String(format: "%.0f", $0.rpm) }.joined(separator: " / ") + " RPM")
                .monospacedDigit()
        }
        .font(.subheadline)
        .padding(11)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 11))
    }

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("偏好设置", systemImage: "slider.horizontal.3")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版本")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("刷新频率").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Picker("刷新频率", selection: $monitor.interval) {
                    Text("1 秒").tag(1000)
                    Text("2 秒").tag(2000)
                    Text("5 秒").tag(5000)
                    Text("10 秒").tag(10000)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("菜单栏项目").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("选择显示内容").font(.caption2).foregroundStyle(.secondary)
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 7), GridItem(.flexible(), spacing: 7)], spacing: 7) {
                    ForEach(MenuContent.allCases) { item in
                        let enabled = monitor.menuItems.contains(item)
                        Button {
                            if enabled { monitor.menuItems.remove(item) }
                            else { monitor.menuItems.insert(item) }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: menuIcon(item))
                                    .font(.caption).frame(width: 14)
                                Text(menuTitle(item)).font(.caption2.weight(.medium)).lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                Spacer(minLength: 0)
                                if enabled {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption2)
                                }
                            }
                            .foregroundStyle(enabled ? Color.primary : Color.secondary)
                            .padding(.horizontal, 9).frame(height: 37)
                            .background(enabled ? accent.opacity(0.14) : Color.primary.opacity(0.04),
                                        in: RoundedRectangle(cornerRadius: 9))
                            .overlay {
                                RoundedRectangle(cornerRadius: 9)
                                    .strokeBorder(enabled ? accent.opacity(0.38) : Color.primary.opacity(0.07))
                            }
                        }
                        .buttonStyle(ChipBarPressStyle())
                        .accessibilityLabel("\(item.title)，\(enabled ? "已显示" : "未显示")")
                        .animation(ChipBarMotion.optional(ChipBarMotion.selection,
                                                          reduceMotion: reduceMotion),
                                   value: enabled)
                    }
                }
                if monitor.menuItems.contains(.power) {
                    Picker("菜单栏功率", selection: $monitor.menuMetric) {
                        ForEach(PowerMetric.allCases) { Text($0.title).tag($0) }
                    }.font(.caption)
                }
                if monitor.ssd.enabled {
                    Toggle("显示 SSD 温度", isOn: Binding(
                        get: { monitor.ssd.showInMenu },
                        set: { monitor.ssd.showInMenu = $0 }))
                        .font(.caption)
                }
            }

            Divider()
            SSDSettings(ssd: monitor.ssd)

            Text("默认自动发现 macmon 与 smartctl；已保存的兼容配置继续生效。功率为芯片读数，不代表整机插座输入功率。")
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !monitor.connected {
                Text("macmon 未连接，请检查安装后重试。")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }

    private func menuTitle(_ item: MenuContent) -> String {
        switch item {
        case .logo: return "Logo"
        case .power: return "功率"
        case .utilization: return "CPU / GPU"
        case .memory: return "内存"
        case .cpuTemperature: return "CPU 温度"
        case .fans: return "风扇"
        case .network: return "网络速率"
        case .disk: return "磁盘速率"
        case .externalDisk: return "外置磁盘"
        }
    }

    private func menuIcon(_ item: MenuContent) -> String {
        switch item {
        case .logo: return "bolt.fill"
        case .power: return "bolt"
        case .utilization: return "cpu"
        case .memory: return "memorychip"
        case .cpuTemperature: return "thermometer"
        case .fans: return "fanblades"
        case .network: return "arrow.up.arrow.down"
        case .disk: return "internaldrive"
        case .externalDisk: return "externaldrive"
        }
    }

    @ViewBuilder private var footer: some View {
            VStack {
            Divider()
            HStack {
                Button { state.showSettings = true } label: {
                    HStack(spacing: 6) {
                        Label("设置", systemImage: "slider.horizontal.3")
                        Image(systemName: "chevron.right").font(.caption2)
                    }
                }
                .accessibilityLabel("打开设置页面")
                Spacer()
                Button(monitor.paused ? "继续" : "暂停") { monitor.togglePause() }
                Button("退出") { monitor.stop(forQuit: true); NSApplication.shared.terminate(nil) }
            }.buttonStyle(ChipBarPressStyle()).font(.subheadline)
            }
    }

    private var trendAxisDates: [Date] {
        guard let first = monitor.history.first?.date, let last = monitor.history.last?.date else { return [] }
        guard last > first else { return [first] }
        return [first, first.addingTimeInterval(last.timeIntervalSince(first) / 2), last]
    }

    private var trendDateFormat: Date.FormatStyle {
        let duration = (monitor.history.last?.date ?? Date()).timeIntervalSince(monitor.history.first?.date ?? Date())
        return duration >= 120 ? .dateTime.hour().minute() : .dateTime.minute().second()
    }

    private var average: Double? {
        let values = monitor.history.compactMap { $0.power(state.chartMetric) }
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    // Do not draw a line across sleep, restart or missing metric gaps.
    private var chartPoints: [PowerTrendPlot.Point] {
        var segment = 0
        var previous: Sample?
        var points: [PowerTrendPlot.Point] = []
        for sample in monitor.history {
            if let previous, sample.date.timeIntervalSince(previous.date) > Double(monitor.interval) / 1000 * 2.5 || previous.power(state.chartMetric) == nil {
                segment += 1
            }
            if let power = sample.power(state.chartMetric) {
                points.append(PowerTrendPlot.Point(date: sample.date, power: power, segment: segment))
            }
            previous = sample
        }
        return points
    }

    private func value(_ number: Double?) -> String { number.map { String(format: "%.1f", $0) } ?? "—" }
    private func temperature(_ number: Double?) -> String {
        guard monitor.connected, let number else { return "不可用" }
        return String(format: "%.1f °C", number)
    }
}

private struct MemoryPressureBadge: View {
    let level: MemoryPressureLevel

    private let colors: [Color] = [.green, .yellow, .red]
    private var activeIndex: Int? {
        switch level {
        case .normal: return 0
        case .warning: return 1
        case .critical: return 2
        case .unknown: return nil
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            HStack(spacing: 2) {
                ForEach(colors.indices, id: \.self) { index in
                    Capsule().fill(index == activeIndex ? colors[index] : colors[index].opacity(0.22))
                        .frame(width: 7, height: 4)
                }
            }
            Text(level.title).font(.caption2.weight(.medium)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 7).padding(.vertical, 5)
        .background(.quaternary, in: Capsule())
        .accessibilityLabel("系统内存压力：\(level.title)")
        .help("系统内存压力：\(level.title)")
    }
}
