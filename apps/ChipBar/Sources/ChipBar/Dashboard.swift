import SwiftUI
import QuartzCore
import ChipBarCore

enum DashboardLayout {
    static let width: CGFloat = 378
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
    @Published var sidePanel: DashboardSidePanelKind? = nil
    @Published var selectedExternalVolumeID: String? = nil
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
        sidePanel = nil
        selectedExternalVolumeID = nil
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
    func toggleApplications() {
        showApplications.toggle()
        applicationsExpansion = showApplications ? 1 : 0
    }
    func toggleSettings() { showSettings.toggle() }
}

struct Dashboard: View {
    @ObservedObject var monitor: Monitor
    @StateObject private var state: DashboardState
    @StateObject private var updater = ChipBarUpdater.shared
    @StateObject private var powerReading = ChipBarPowerFlowModel.shared
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
        VStack(alignment: .leading, spacing: 10) {
            header
            hero
            powerCards
            CPUCoreUsageSection(samplingInterval: monitor.interval,
                                active: monitor.dashboardVisible && !monitor.paused && !monitor.sleeping)
            HStack(spacing: 8) {
                homeFanTile
                DashboardANEStrip(power: monitor.sample?.ane, connected: monitor.connected)
            }
            StorageCapacitySection(state: state)
            HStack(spacing: 8) {
                sidePanelEntry("电源与功率", icon: "bolt.horizontal.circle", kind: .power,
                               trailingValue: powerReading.reading.systemWatts)
                sidePanelEntry("应用占用", icon: "square.stack.3d.up", kind: .applications)
            }
            errorPanel
            Text(monitor.status).font(.caption).foregroundStyle(.secondary)
            footer
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The only secondary page: system facts, hardware details and settings.
    /// Home remains compact, with internal/external storage space bars.
    private var settingsScreen: some View {
        VStack(alignment: .leading, spacing: 10) {
            settingsNavigation
            MacHardwareInformationSection(chip: monitor.sample?.chip ?? monitor.hardware)
            fanOverview
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
                Image(systemName: "chevron.left")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 30, height: 30)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 9))
                    .contentShape(RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(ChipBarPressStyle())
            .accessibilityLabel("返回监控面板")
            VStack(alignment: .leading, spacing: 2) {
                Text("设备与设置")
                    .font(.headline)
                Text("硬件概览 · 显示偏好")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "slider.horizontal.3")
                .foregroundStyle(accent)
                .font(.system(size: 15))
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
        return String(format: "%.1f / %.1f GB", memory.usedGiB, memory.totalGiB)
    }

    /// One and only one power history chart: the headline and real rolling
    /// 10-minute graph form the dashboard's single information focal point.
    // The headline and y-axis now share the same top boundary. Both columns
    // reserve exactly 70 pt, so loading/empty states do not shift the header.
    private var totalPowerHeadline: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("芯片总功率")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(height: 14, alignment: .topLeading)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                AnimatedMetricValue(value: monitor.connected ? monitor.sample?.total : nil)
                    .font(.system(size: 27, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text("W")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(height: 34, alignment: .leading)
            Text("CPU + GPU + ANE")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(height: 12, alignment: .leading)
        }
        .frame(width: 82, height: 70, alignment: .topLeading)
    }

    @ViewBuilder private var totalPowerChart: some View {
        if monitor.powerChart.points.isEmpty {
            Text("等待功率采样")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 70)
        } else {
            PowerTrendPlot(
                points: monitor.powerChart.points,
                maximum: monitor.powerChart.maximum,
                timeline: monitor.powerChart.timeline,
                accent: accent
            )
            .frame(height: 70)
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 4) {
                totalPowerHeadline
                totalPowerChart
            }
            .frame(height: 70, alignment: .top)
            HStack(spacing: 8) {
                Text("最近 10 分钟")
                Spacer()
                Text("均值 \(value(monitor.powerChart.average)) W")
            }
            .font(.system(size: 9))
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder private var powerCards: some View {
        HStack(alignment: .top, spacing: 8) {
            DashboardRunway(
                title: "CPU", percentage: monitor.connected ? monitor.sample?.cpuUtilization : nil,
                color: accent,
                subtitle: wattage(monitor.connected ? monitor.sample?.cpu : nil),
                detail: temperatureSummary(monitor.connected ? monitor.sample?.cpuTemperature : nil))
            DashboardRunway(
                title: "GPU", percentage: monitor.connected ? monitor.sample?.gpuUtilization : nil,
                color: accent.opacity(0.78),
                subtitle: wattage(monitor.connected ? monitor.sample?.gpu : nil),
                detail: temperatureSummary(monitor.connected ? monitor.sample?.gpuTemperature : nil))
            DashboardRunway(
                title: "内存", percentage: monitor.connected ? monitor.sample?.memory?.usedPercent : nil,
                color: MemoryPressureRingStyle.tint(for: monitor.memoryPressure),
                subtitle: monitor.connected ? memoryCapacitySummary : "内存 —",
                detail: "统一内存",
                pressureStatus: monitor.memoryPressure.title)
        }
    }

    private func sidePanelEntry(_ title: String, icon: String,
                                kind: DashboardSidePanelKind,
                                trailingValue: Double? = nil) -> some View {
        let selected = state.sidePanel == kind
        return Button {
            if kind == .applications && state.sidePanel != .applications {
                // The sidecar may show five rows without growing the main window.
                state.showApplications = true
                state.applicationsExpansion = 1
            }
            state.sidePanel = selected ? nil : kind
        } label: {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(accent)
                Text(title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 2)
                if kind == .power {
                    Text(wattage(trailingValue))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(.primary)
                }
                Image(systemName: selected ? "chevron.right" : "rectangle.on.rectangle")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 11)
            .frame(height: 41)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(selected ? accent.opacity(0.42) : Color.primary.opacity(0.05),
                                  lineWidth: 0.7)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(ChipBarPressStyle())
        .accessibilityLabel("\(title)，\(kind == .power ? wattage(trailingValue) : "")，\(selected ? "收起" : "在侧边卡片展开")")
        .task(id: monitor.dashboardVisible && !monitor.paused && !monitor.sleeping) {
            guard kind == .power, monitor.dashboardVisible,
                  !monitor.paused, !monitor.sleeping else { return }
            await powerReading.watch()
        }
    }

    private func wattage(_ power: Double?) -> String {
        guard let power, power.isFinite else { return "— W" }
        return String(format: "%.1f W", power)
    }

    private func temperatureSummary(_ temperature: Double?) -> String {
        guard let temperature, temperature.isFinite else { return "温度不可用" }
        return String(format: "%.1f°C", temperature)
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

    private var homeFanTile: some View {
        let fans = monitor.connected ? monitor.sample?.fans ?? [] : []
        return HStack(spacing: 7) {
            Image(systemName: "fanblades")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(accent)
            Text("风扇")
                .font(.caption.weight(.medium))
            Spacer(minLength: 2)
            Text(fans.isEmpty ? "— RPM" :
                 fans.map { String(format: "%.0f", $0.rpm) }.joined(separator: "/") + " RPM")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 11)
        .frame(maxWidth: .infinity)
        .frame(height: 43)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }

    private var fanOverview: some View {
        HStack(spacing: 9) {
            Label("风扇转速", systemImage: "fanblades")
                .font(.caption.weight(.medium))
            Spacer()
            let fans = monitor.connected ? monitor.sample?.fans ?? [] : []
            Text(fans.isEmpty ? "不可用" :
                 fans.map { String(format: "%.0f", $0.rpm) }.joined(separator: " / ") + " RPM")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(fans.isEmpty ? Color.secondary : Color.primary)
        }
        .padding(.horizontal, 12)
        .frame(height: 35)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 11))
    }

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("采样频率", systemImage: "clock.arrow.circlepath")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("影响刷新与功耗")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                RefreshIntervalSelector(selection: $monitor.interval)
            }
            .padding(12)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 13))

            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    Label("菜单栏显示", systemImage: "menubar.rectangle")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(monitor.menuItems.count) / 8 已显示")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                    GridRow {
                        menuChoice(.logo)
                        menuChoice(.power)
                        menuChoice(.utilization)
                    }
                    GridRow {
                        menuChoice(.memory)
                        menuChoice(.cpuTemperature)
                        menuChoice(.fans)
                    }
                    GridRow {
                        menuChoice(.network)
                        menuChoice(.disk).gridCellColumns(2)
                    }
                }
                if monitor.menuItems.contains(.power) {
                    ChipBarPowerSelection(selection: $monitor.menuMetric)
                }
                Toggle("菜单栏 SSD 温度", isOn: Binding(
                    get: { monitor.ssd.menuTemperaturesEnabled },
                    set: { monitor.ssd.menuTemperaturesEnabled = $0 }
                ))
                    .toggleStyle(ChipBarGlassToggleStyle())
                    .font(.caption.weight(.medium))
                    .accessibilityHint("没有外置硬盘连接时也可以随时关闭")
            }
            .padding(12)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 13))

            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    Label("应用更新", systemImage: "arrow.triangle.2.circlepath")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
                         as? String ?? "开发版本")
                        .font(.caption2).foregroundStyle(.secondary)
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
            .padding(12)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 13))

            if !monitor.connected {
                Text("macmon 未连接，请检查安装后重试。")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func menuChoice(_ item: MenuContent) -> some View {
        let enabled = monitor.menuItems.contains(item)
        return Button {
            withAnimation(ChipBarMotion.optional(ChipBarMotion.selection,
                                                 reduceMotion: reduceMotion)) {
                if enabled { monitor.menuItems.remove(item) }
                else { monitor.menuItems.insert(item) }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: menuIcon(item))
                    .font(.system(size: 11))
                    .frame(width: 13)
                    .foregroundStyle(enabled ? accent : Color.secondary)
                Text(menuTitle(item))
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                if enabled {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(accent)
                }
            }
            .foregroundStyle(enabled ? Color.primary : Color.secondary)
            .padding(.horizontal, 8)
            .frame(height: 34)
            .frame(maxWidth: .infinity)
            .background(enabled ? accent.opacity(0.13) : Color.primary.opacity(0.035),
                        in: RoundedRectangle(cornerRadius: 9))
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(enabled ? accent.opacity(0.30) : Color.primary.opacity(0.05),
                                  lineWidth: 0.75)
            }
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(ChipBarPressStyle())
        .accessibilityLabel(item.title)
        .accessibilityValue(enabled ? "已显示" : "未显示")
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

    /// Pin the x-axis to a real 10-minute window ending at the latest
    /// received sample. On startup, a few data points occupy only the most
    /// recent part of the plot instead of stretching to its entire width.
    private func value(_ number: Double?) -> String { number.map { String(format: "%.1f", $0) } ?? "—" }
    private func temperature(_ number: Double?) -> String {
        guard monitor.connected, let number else { return "不可用" }
        return String(format: "%.1f °C", number)
    }
}

