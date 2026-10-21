import SwiftUI
import QuartzCore
import ChipBarCore

enum DashboardMotion {
    static let duration = 0.20
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
    @Published var ssdExpansion = CommandLine.arguments.contains("--ssd-details") ? 1.0 : 0.0
    @Published var ssdDetailsHeight: CGFloat = 0
    @Published var settingsExpansion = 0.0
    @Published var settingsHeight: CGFloat = 0
    @Published var applicationMetric: ApplicationResource = CommandLine.arguments.contains("--apps-gpu") ? .gpu : CommandLine.arguments.contains("--apps-ane") ? .ane : .cpu
    init(showSettings: Bool = false) {
        self.showSettings = showSettings
        settingsExpansion = showSettings ? 1 : 0
    }
    func toggleApplications() { showApplications.toggle() }
    func toggleSettings() { showSettings.toggle() }
}

struct Dashboard: View {
    @ObservedObject var monitor: Monitor
    @StateObject private var state: DashboardState
    private let accent = Color(red: 0.22, green: 0.65, blue: 0.79)
    private let appIcon = Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
        .flatMap { NSImage(contentsOf: $0) }

    init(monitor: Monitor, showSettings: Bool = false, state: DashboardState? = nil) {
        self.monitor = monitor
        _state = StateObject(wrappedValue: state ?? DashboardState(showSettings: showSettings))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            hero
            powerCards
            ApplicationUsageSection(monitor: monitor, state: state)
            trend
            temperatures
            systemMemory
            connectivity
            SSDSection(ssd: monitor.ssd, state: state)
            errorPanel
            Text(monitor.status).font(.caption).foregroundStyle(.secondary)
            VStack(spacing: 0) {
                settingsPanel
                    .fixedSize(horizontal: false, vertical: true)
                    .background(GeometryReader { geometry in
                        Color.clear
                            .onAppear { state.settingsHeight = geometry.size.height }
                            .onChange(of: geometry.size.height) { state.settingsHeight = $0 }
                    })
                    .padding(.bottom, 12)
                    .frame(height: (state.settingsHeight + 12) * state.settingsExpansion, alignment: .top)
                    .opacity(state.settingsExpansion).clipped()
                    .accessibilityHidden(!state.showSettings)
                    .disabled(!state.showSettings)
                footer
            }
        }
        .padding(16).frame(width: 390)
        .fixedSize(horizontal: false, vertical: true)
        // Keep the document at the top while AppKit animates the window height.
        .frame(maxHeight: .infinity, alignment: .topLeading)
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
                }
                Spacer()
                Circle().fill(monitor.connected ? Color.green : Color.orange).frame(width: 6, height: 6)
                Text(monitor.paused ? "已暂停" : monitor.connected ? "实时" : "等待数据")
                    .font(.caption).foregroundStyle(.secondary)
            }

    }

    @ViewBuilder private var hero: some View {
            VStack(alignment: .leading, spacing: 6) {
                Text("芯片合计功率").font(.subheadline).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(value(monitor.connected ? monitor.sample?.total : nil))
                        .font(.system(size: 36, weight: .medium, design: .rounded)).monospacedDigit()
                    Text("W").font(.title3).foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "bolt.fill").font(.title).foregroundStyle(accent.opacity(0.6))
                }
                Text("CPU + GPU + ANE · 非插座输入功率")
                    .font(.caption).foregroundStyle(.secondary)
            }

    }

    @ViewBuilder private var powerCards: some View {
            HStack(spacing: 10) {
                powerCard("CPU", monitor.sample?.cpu, "cpu", monitor.sample?.cpuUtilization)
                powerCard("GPU", monitor.sample?.gpu, "square.stack.3d.up", monitor.sample?.gpuUtilization)
                powerCard("ANE", monitor.sample?.ane, "sparkles", nil)
            }

    }

    @ViewBuilder private var trend: some View {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("功率趋势").font(.subheadline.weight(.medium))
                    Spacer()
                    Picker("趋势指标", selection: $state.chartMetric) {
                        ForEach(PowerMetric.allCases) { Text($0.title).tag($0) }
                    }.labelsHidden().pickerStyle(.menu).fixedSize()
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
                }
                HStack {
                    Text("最近 10 分钟 · W")
                    Spacer()
                    Text("均值 \(value(average)) W")
                }.font(.caption2).foregroundStyle(.secondary)
            }

    }

    @ViewBuilder private var temperatures: some View {
            HStack {
                Label("CPU \(temperature(monitor.sample?.cpuTemperature))", systemImage: "thermometer.medium")
                Spacer()
                Text("GPU \(temperature(monitor.sample?.gpuTemperature))")
            }.font(.subheadline).monospacedDigit()

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

    private var connectivity: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("实时网速", systemImage: "network")
                Spacer()
                Text(monitor.network.interfaces.joined(separator: " + "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            HStack {
                Text("↓ \(NetworkRate.text(monitor.network.rate?.download))")
                Spacer()
                Text("↑ \(NetworkRate.text(monitor.network.rate?.upload))")
            }.monospacedDigit()
            Divider()
            HStack {
                Label("风扇", systemImage: "fanblades")
                Spacer()
                let fans = monitor.connected ? monitor.sample?.fans ?? [] : []
                Text(fans.isEmpty ? "不可用" : fans.map { String(format: "%.0f", $0.rpm) }.joined(separator: " / ") + " RPM")
                    .monospacedDigit()
            }
        }.font(.subheadline).padding(12)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder private var settingsPanel: some View {
                VStack(alignment: .leading, spacing: 10) {
                    Text("ChipBar \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版本")")
                        .font(.caption).foregroundStyle(.secondary)
                    Picker("刷新间隔", selection: $monitor.interval) {
                        Text("1 秒").tag(1000); Text("2 秒").tag(2000)
                        Text("5 秒").tag(5000); Text("10 秒").tag(10000)
                    }.pickerStyle(.segmented)
                    Text("菜单栏显示").font(.subheadline.weight(.medium))
                    Picker("功率指标", selection: $monitor.menuMetric) {
                        ForEach(PowerMetric.allCases) { Text($0.title).tag($0) }
                    }.disabled(!monitor.menuItems.contains(.power))
                    ForEach(MenuContent.allCases) { item in
                        Toggle(item.title, isOn: Binding(
                            get: { monitor.menuItems.contains(item) },
                            set: { enabled in
                                if enabled { monitor.menuItems.insert(item) } else { monitor.menuItems.remove(item) }
                            }))
                    }
                    Toggle("SSD 综合温度", isOn: Binding(get: { monitor.ssd.showInMenu }, set: { monitor.ssd.showInMenu = $0 }))
                    Text("两排紧凑显示；风扇显示最高转速，悬停可查看全部读数。SSD 温度需启用下方监控，多盘取最高温。")
                        .font(.caption2).foregroundStyle(.secondary)
                    Text("硬盘总速度合计内置和外接物理盘；外置速度单列 ER / EW，多盘取合计，未连接时隐藏，不需要开启 SMART。")
                        .font(.caption2).foregroundStyle(.secondary)
                    Text("网速与菜单栏磁盘速度按所选间隔统一刷新，网速合计活跃以太网 / Wi-Fi 接口，包含局域网传输。CPU / GPU 占用率为采样期间活跃时间占比。ANE 暂无整体占用率。")
                        .font(.caption2).foregroundStyle(.secondary)
                    HStack {
                        Button("选择 macmon…") { monitor.chooseExecutable() }
                        Spacer()
                        Button("自动查找") { monitor.useDefaultPath() }
                    }
                    Text(monitor.executablePath.isEmpty ? "尚未找到 macmon" : monitor.executablePath)
                        .font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                    SSDSettings(ssd: monitor.ssd)
                    Text("缺失指标显示 —。零值只表示 macmon 返回零，不能据此确认传感器支持。新芯片请先实测。")
                        .font(.caption2).foregroundStyle(.secondary)
                }.padding(12).background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }


    @ViewBuilder private var footer: some View {
            VStack {
            Divider()
            HStack {
                Button { state.toggleSettings() } label: { Label("设置", systemImage: "slider.horizontal.3") }
                Spacer()
                Button(monitor.paused ? "继续" : "暂停") { monitor.togglePause() }
                Button("退出") { monitor.stop(forQuit: true); NSApplication.shared.terminate(nil) }
            }.buttonStyle(.borderless).font(.subheadline)
            }
    }

    private func powerCard(_ title: String, _ power: Double?, _ icon: String, _ utilization: Double?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon).font(.caption).foregroundStyle(.secondary)
            Text("\(value(monitor.connected ? power : nil)) W")
                .font(.system(.body, design: .rounded).weight(.semibold)).monospacedDigit()
            Text(title == "ANE" ? "占用率不可用" : "占用 \(monitor.connected ? utilization.map { String(format: "%.1f%%", $0) } ?? "—" : "—")")
                .font(.caption).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
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
