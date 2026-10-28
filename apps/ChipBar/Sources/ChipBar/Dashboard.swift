import SwiftUI
import QuartzCore
import ChipBarCore

enum DashboardLayout {
    static let width: CGFloat = 420
}

enum DashboardMotion {
    static let duration = 0.20
    static let navigation = 0.24
    // The page slide finishes before the glass window settles to its new size.
    static let navigationResize = 0.34
    static let navigationSpringCurve = CAMediaTimingFunction(controlPoints: 0.22, 0.72, 0.30, 1.00)
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
    @StateObject private var updater = ChipBarUpdater.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let accent = Color(red: 0.22, green: 0.65, blue: 0.79)
    private let appIcon = Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
        .flatMap { NSImage(contentsOf: $0) }

    init(monitor: Monitor, showSettings: Bool = false, state: DashboardState? = nil) {
        self.monitor = monitor
        _state = StateObject(wrappedValue: state ?? DashboardState(showSettings: showSettings))
    }

    private var showsDeviceAndSettings: Bool {
        state.showSettings || state.showSystemDetails
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if showsDeviceAndSettings {
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
        // One navigation state and one animation transaction: having a second
        // animation for the old System page could briefly restyle the material
        // during Settings transitions.
        .animation(ChipBarMotion.optional(ChipBarMotion.navigation, reduceMotion: reduceMotion),
                   value: showsDeviceAndSettings)
    }

    private var monitoringScreen: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            hero
            powerCards
            CPUCoreUsageSection(samplingInterval: monitor.interval,
                                active: monitor.dashboardVisible && !monitor.paused && !monitor.sleeping)
            ApplicationUsageSection(monitor: monitor, state: state)
            trend
            StorageCapacitySection()
            errorPanel
            Text(monitor.status).font(.caption).foregroundStyle(.secondary)
            footer
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The only secondary page: system facts, hardware details and settings.
    /// Home remains compact, with internal/external storage space bars.
    private var settingsScreen: some View {
        VStack(alignment: .leading, spacing: 12) {
            settingsNavigation
            MacHardwareInformationSection(
                chip: monitor.sample?.chip ?? monitor.hardware)
            HStack {
                Label("硬件状态", systemImage: "cpu")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            fanOverview
            if monitor.ssd.enabled {
                SSDSection(ssd: monitor.ssd, state: state)
            } else {
                HStack(spacing: 8) {
                    Label("外接 SSD 状态", systemImage: "externaldrive")
                    Spacer()
                    Text("监控未启用").foregroundStyle(.secondary)
                }
                .font(.subheadline)
                .padding(11)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 11))
            }
            settingsPanel
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var settingsNavigation: some View {
        HStack(spacing: 10) {
            Button {
                if state.showSettings { state.showSettings = false }
                else { state.showSystemDetails = false }
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
            Text("设备与设置").font(.headline)
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

    /// Keep RAM capacity outside the shared ring box while leaving the
    /// memory usage percentage and macOS pressure-colored stroke unchanged.
    private var memoryCapacitySummary: String {
        guard monitor.connected, let memory = monitor.sample?.memory else { return "内存 —" }
        return String(format: "内存 %.1f/%.1f GB", memory.usedGiB, memory.totalGiB)
    }

    @ViewBuilder private var hero: some View {
            VStack(alignment: .leading, spacing: 6) {
                Text("芯片合计功率").font(.subheadline).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    AnimatedMetricValue(value: monitor.connected ? monitor.sample?.total : nil, decimals: 1)
                        .font(.system(size: 36, weight: .medium, design: .rounded)).monospacedDigit()
                    Text("W").font(.title3).foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Text(memoryCapacitySummary)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .layoutPriority(-1)
                        .help("系统内存已用容量 / 总容量")
                    Image(systemName: "bolt.fill").font(.title).foregroundStyle(accent.opacity(0.6))
                }
                Text("CPU + GPU + ANE · 非整机插座输入功率")
                    .font(.caption).foregroundStyle(.secondary)
            }

    }

    /// Three matching cards keep wattage primary and the bounded occupancy
    /// gauges in equally sized top-trailing slots. No second ring row.
    @ViewBuilder private var powerCards: some View {
        HStack(alignment: .top, spacing: 8) {
            PowerMetricCard(title: "CPU", power: monitor.sample?.cpu,
                            connected: monitor.connected, icon: "cpu",
                            ringTitle: "CPU 占用", ringCaption: "",
                            utilization: monitor.sample?.cpuUtilization, ringTint: accent,
                            temperature: monitor.sample?.cpuTemperature, showsTemperature: true,
                            recentPowers: monitor.history.suffix(24).compactMap { $0.power(.cpu) })
            PowerMetricCard(title: "GPU", power: monitor.sample?.gpu,
                            connected: monitor.connected, icon: "square.stack.3d.up",
                            ringTitle: "GPU 占用", ringCaption: "",
                            utilization: monitor.sample?.gpuUtilization, ringTint: accent.opacity(0.78),
                            temperature: monitor.sample?.gpuTemperature, showsTemperature: true,
                            recentPowers: monitor.history.suffix(24).compactMap { $0.power(.gpu) })
            PowerMetricCard(title: "ANE", power: monitor.sample?.ane,
                            connected: monitor.connected, icon: "sparkles",
                            ringTitle: "内存占用", ringCaption: "内存",
                            utilization: monitor.sample?.memory?.usedPercent,
                            ringTint: MemoryPressureRingStyle.tint(for: monitor.memoryPressure),
                            ringStatus: monitor.memoryPressure.title,
                            recentPowers: monitor.history.suffix(24).compactMap { $0.ane })
        }
    }

    @ViewBuilder private var trend: some View {
            VStack(alignment: .leading, spacing: 7) {
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
                        .frame(maxWidth: .infinity).frame(height: 64)
                } else {
                    PowerTrendPlot(points: chartPoints,
                        maximum: max(1, (monitor.history.compactMap { $0.power(state.chartMetric) }.max() ?? 1) * 1.15),
                        axisDates: trendAxisDates, dateFormat: trendDateFormat, accent: accent)
                    .frame(height: 64)
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
                RefreshIntervalSelector(selection: $monitor.interval)
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
                                ChipBarMiniSwitch(enabled: enabled, compact: true)
                            }
                            .foregroundStyle(enabled ? Color.primary : Color.secondary)
                            .padding(.horizontal, 9)
                            .frame(height: 39)
                            .background(Color.primary.opacity(enabled ? 0.09 : 0.035),
                                        in: RoundedRectangle(cornerRadius: 10))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(Color.primary.opacity(enabled ? 0.18 : 0.07),
                                                  lineWidth: 0.7)
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
                    ChipBarPowerSelection(selection: $monitor.menuMetric)
                }
                if monitor.ssd.enabled {
                    Toggle("显示 SSD 温度", isOn: Binding(
                        get: { monitor.ssd.showInMenu },
                        set: { monitor.ssd.showInMenu = $0 }))
                        .toggleStyle(ChipBarGlassToggleStyle())
                }
            }

            Divider()
            SSDSettings(ssd: monitor.ssd)

            Divider()
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Label("应用更新", systemImage: "arrow.triangle.2.circlepath")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    if updater.busy { ProgressView().controlSize(.small) }
                    Button("检查更新") { updater.check() }
                        .font(.caption)
                        .disabled(updater.busy)
                }
                Text(updater.status)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let version = updater.availableVersion {
                    Button {
                        updater.install()
                    } label: {
                        Label("下载并安装 ChipBar \(version)", systemImage: "arrow.down.app")
                    }
                    .font(.caption.weight(.medium))
                    .disabled(updater.busy)
                }
            }

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
                        Label("设备与设置", systemImage: "slider.horizontal.3")
                        Image(systemName: "chevron.right").font(.caption2)
                    }
                }
                .accessibilityLabel("打开设备信息与设置页面")
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

