import Foundation
import SwiftUI
import WidgetKit

/// All ten ChipBar dashboard modules are independent, selectable widgets in
/// the macOS desktop / Notification Center widget gallery. The system owns
/// placement, sizing and update budgets.
private enum ChipBarWidgetTile: String, CaseIterable {
    case overview, powerTrend, cpu, gpu, memory, cpuCores, fan, ane, storage, powerSupply, applications

    var title: String {
        switch self {
        case .overview: return "ChipBar 仪表盘"
        case .powerTrend: return "芯片功率趋势"
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .memory: return "内存"
        case .cpuCores: return "CPU 各核心"
        case .fan: return "风扇"
        case .ane: return "ANE"
        case .storage: return "储存空间"
        case .powerSupply: return "内部功率"
        case .applications: return "应用占用"
        }
    }

    /// The descriptor-query path evaluates WidgetConfiguration before any
    /// timeline is rendered. WidgetKit's .description(_:) cannot handle
    /// LocalizedStringKey interpolation and can fatalError during that query.
    /// Keep gallery metadata backed by direct, static localization keys.
    var galleryTitle: LocalizedStringKey {
        switch self {
        case .overview: return "ChipBar · 仪表盘"
        case .powerTrend: return "ChipBar · 芯片功率趋势"
        case .cpu: return "ChipBar · CPU"
        case .gpu: return "ChipBar · GPU"
        case .memory: return "ChipBar · 内存"
        case .cpuCores: return "ChipBar · CPU 各核心"
        case .fan: return "ChipBar · 风扇"
        case .ane: return "ChipBar · ANE"
        case .storage: return "ChipBar · 储存空间"
        case .powerSupply: return "ChipBar · 内部功率"
        case .applications: return "ChipBar · 应用占用"
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "waveform.path.ecg.rectangle"
        case .powerTrend: return "chart.xyaxis.line"
        case .cpu: return "cpu"
        case .gpu: return "square.stack.3d.up"
        case .memory: return "memorychip"
        case .cpuCores: return "chart.bar.xaxis"
        case .fan: return "fanblades"
        case .ane: return "sparkle"
        case .storage: return "internaldrive"
        case .powerSupply: return "bolt.horizontal.circle"
        case .applications: return "square.stack.3d.up"
        }
    }

    var metric: String {
        switch self {
        case .overview: return "chip"
        case .powerTrend: return "chip"
        case .cpu: return "cpuPower"
        case .gpu: return "gpuPower"
        case .memory: return "ramPercentage"
        case .cpuCores: return "cpuUsage"
        case .fan: return "fanRPM"
        case .ane: return "anePower"
        case .storage: return "storageFreeGB"
        case .powerSupply: return "internalPower"
        case .applications: return "cpuUsage"
        }
    }
}

/// The companion app publishes a sanitized snapshot only to its own App Group.
/// The widget neither polls macmon nor accesses the SMC or running processes.
private struct WidgetTelemetry {
    // The distributed binary is ad-hoc signed and intentionally has no
    // application-groups entitlement. Looking up an unentitled group in
    // WidgetKit can make chronod reject the entire extension before its
    // widgets become visible in the gallery.
    let fields: [String: Any]
    static var current: WidgetTelemetry {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first
        let url = directory?.appendingPathComponent("ChipBar/telemetry.json")
        guard let url, let data = try? Data(contentsOf: url),
              data.count <= 128 * 1024,
              let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return WidgetTelemetry(fields: [:]) }
        return WidgetTelemetry(fields: decoded)
    }

    func label(_ key: String) -> String? {
        guard let text = fields[key] as? String, !text.isEmpty else { return nil }
        return text
    }

    func allNames(_ key: String, limit: Int = 64) -> [String] {
        guard let raw = fields[key] as? [String] else { return [] }
        return Array(raw.prefix(limit))
    }

    func number(_ key: String) -> Double? {
        guard let number = fields[key] as? NSNumber else { return nil }
        let value = number.doubleValue
        return value.isFinite && value >= 0 ? value : nil
    }

    func values(_ key: String, limit: Int = 24) -> [Double] {
        guard let raw = fields[key] as? [NSNumber] else { return [] }
        return Array(raw.prefix(limit)).map(\.doubleValue).filter { $0.isFinite && $0 >= 0 }
    }

    func names(_ key: String, limit: Int = 3) -> [String] {
        guard let raw = fields[key] as? [String] else { return [] }
        return Array(raw.prefix(limit)).filter { !$0.isEmpty }
    }

    var sampledAt: Date? {
        guard let time = number("timestamp"), time > 0 else { return nil }
        return Date(timeIntervalSince1970: time)
    }

    func stale(at date: Date) -> Bool {
        guard let sampledAt else { return true }
        let age = date.timeIntervalSince(sampledAt)
        return age < -60 || age > 20 * 60
    }
}

private struct ChipBarWidgetEntry: TimelineEntry {
    let date: Date
    let telemetry: WidgetTelemetry
}

private struct ChipBarWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> ChipBarWidgetEntry {
        ChipBarWidgetEntry(date: .now, telemetry: WidgetTelemetry(fields: [:]))
    }
    func getSnapshot(in context: Context, completion: @escaping (ChipBarWidgetEntry) -> Void) {
        completion(ChipBarWidgetEntry(date: .now, telemetry: .current))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ChipBarWidgetEntry>) -> Void) {
        let date = Date()
        let entry = ChipBarWidgetEntry(date: date, telemetry: .current)
        // WidgetKit is budgeted by macOS; this is not a live 1–3 s monitor.
        completion(Timeline(entries: [entry], policy: .after(date.addingTimeInterval(15 * 60))))
    }
}

// WidgetKit requires each Widget type to be default-initializable. An
// instance-only tile argument cannot satisfy Widget.init() and fails the
// distributed extension build. A distinct marker type preserves each tile's
// identity when WidgetKit reconstructs it on its own.
private protocol ChipBarWidgetModule {
    static var tile: ChipBarWidgetTile { get }
}
private enum OverviewWidgetModule: ChipBarWidgetModule { static let tile: ChipBarWidgetTile = .overview }
private enum PowerTrendWidgetModule: ChipBarWidgetModule { static let tile: ChipBarWidgetTile = .powerTrend }
private enum CPUWidgetModule: ChipBarWidgetModule { static let tile: ChipBarWidgetTile = .cpu }
private enum GPUWidgetModule: ChipBarWidgetModule { static let tile: ChipBarWidgetTile = .gpu }
private enum MemoryWidgetModule: ChipBarWidgetModule { static let tile: ChipBarWidgetTile = .memory }
private enum CPUCoresWidgetModule: ChipBarWidgetModule { static let tile: ChipBarWidgetTile = .cpuCores }
private enum FanWidgetModule: ChipBarWidgetModule { static let tile: ChipBarWidgetTile = .fan }
private enum ANEWidgetModule: ChipBarWidgetModule { static let tile: ChipBarWidgetTile = .ane }
private enum StorageWidgetModule: ChipBarWidgetModule { static let tile: ChipBarWidgetTile = .storage }
private enum PowerSupplyWidgetModule: ChipBarWidgetModule { static let tile: ChipBarWidgetTile = .powerSupply }
private enum ApplicationsWidgetModule: ChipBarWidgetModule { static let tile: ChipBarWidgetTile = .applications }

private struct ChipBarTelemetryWidget<Module: ChipBarWidgetModule>: Widget {
    init() {}

    var body: some WidgetConfiguration {
        let tile = Module.tile
        return StaticConfiguration(kind: "local.chipbar.telemetry.\(tile.rawValue)",
                                   provider: ChipBarWidgetProvider()) { entry in
            ChipBarWidgetContent(entry: entry, tile: tile)
        }
        .configurationDisplayName(tile.galleryTitle)
        // Deliberately a literal: interpolated .description values can trap
        // with "Formatted text for description is not supported" during
        // chronod's getAllDescriptors query, leaving the gallery empty.
        .description("在桌面或通知中心查看 ChipBar 的最近一次监测快照。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}


private enum GlassTone {
    static let blue = Color(red: 0.39, green: 0.69, blue: 1.00)
    static let lilac = Color(red: 0.79, green: 0.62, blue: 1.00)
    static let gold = Color(red: 1.00, green: 0.78, blue: 0.20)
    static let mint = Color(red: 0.28, green: 0.87, blue: 0.79)
    static let cyan = Color(red: 0.20, green: 0.79, blue: 0.95)
    static let ink = Color.white
    static let secondary = Color(red: 0.68, green: 0.76, blue: 0.88)
}

private enum GlassNumber {
    static func text(_ value: Double?, digits: Int = 1) -> String {
        guard let value, value.isFinite, value >= 0 else { return "—" }
        return String(format: digits == 0 ? "%.0f" : "%.1f", value)
    }

    static func capacity(_ gb: Double?) -> String {
        guard let gb, gb.isFinite, gb >= 0 else { return "—" }
        if gb >= 1000 { return String(format: "%.2f TB", gb / 1000) }
        return String(format: "%.1f GB", gb)
    }
}

private struct GlassWidgetBackground: ViewModifier {
    let purple: Bool

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: purple
                    ? [Color(red: 0.22, green: 0.13, blue: 0.64),
                       Color(red: 0.07, green: 0.08, blue: 0.28),
                       Color(red: 0.20, green: 0.05, blue: 0.28)]
                    : [Color(red: 0.02, green: 0.08, blue: 0.19),
                       Color(red: 0.01, green: 0.16, blue: 0.31),
                       Color(red: 0.02, green: 0.27, blue: 0.40)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(
                colors: purple
                    ? [Color(red: 0.64, green: 0.10, blue: 0.47).opacity(0.48), .clear]
                    : [GlassTone.cyan.opacity(0.24), .clear],
                center: .bottomTrailing,
                startRadius: 3, endRadius: 340)
            RadialGradient(colors: [GlassTone.lilac.opacity(purple ? 0.18 : 0.04), .clear],
                           center: .topLeading, startRadius: 5, endRadius: 260)
        }
    }

    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.containerBackground(for: .widget) { background }
        } else {
            content.background(background)
        }
    }
}

private struct GlassMetricRing: View {
    let value: Double?
    let tint: Color
    let diameter: CGFloat

    private var progress: CGFloat {
        CGFloat(min(1, max(0, (value ?? 0) / 100)))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.13), lineWidth: diameter * 0.12)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(tint, style: StrokeStyle(lineWidth: diameter * 0.12,
                                                 lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: tint.opacity(0.8), radius: diameter * 0.08)
            Text(GlassNumber.text(value, digits: 0))
                .font(.system(size: diameter * 0.245, weight: .bold, design: .rounded))
                .foregroundStyle(GlassTone.ink)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityLabel("使用率 \(GlassNumber.text(value, digits: 0))%")
    }
}

private struct GlassTripleRings: View {
    let cpu: Double?
    let gpu: Double?
    let memory: Double?
    let cpuPower: Double?
    let gpuPower: Double?
    let memoryUsed: Double?
    let compact: Bool

    var body: some View {
        HStack(alignment: .top, spacing: compact ? 8 : 12) {
            item("CPU", value: cpu, power: GlassNumber.text(cpuPower) + " W",
                 tint: GlassTone.blue)
            item("GPU", value: gpu, power: GlassNumber.text(gpuPower) + " W",
                 tint: GlassTone.lilac)
            item("内存", value: memory, power: GlassNumber.text(memoryUsed) + " GB",
                 tint: GlassTone.gold)
        }
        .frame(maxWidth: .infinity)
    }

    private func item(_ label: String, value: Double?, power: String, tint: Color) -> some View {
        VStack(spacing: compact ? 2 : 4) {
            GlassMetricRing(value: value, tint: tint, diameter: compact ? 44 : 59)
            Text(label)
                .font(.system(size: compact ? 9 : 10, weight: .semibold))
                .foregroundStyle(GlassTone.secondary)
            if !compact {
                Text(power)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(GlassTone.ink)
                    .monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct GlassConcentricRings: View {
    let power: Double?
    let cpu: Double?
    let gpu: Double?
    let memory: Double?
    let diameter: CGFloat

    private func arc(_ value: Double?, tint: Color, size: CGFloat) -> some View {
        ZStack {
            Circle().stroke(.white.opacity(0.11), lineWidth: 8)
            Circle()
                .trim(from: 0, to: CGFloat(min(100, max(0, value ?? 0))) / 100)
                .stroke(tint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: tint.opacity(0.52), radius: 5)
        }
        .frame(width: size, height: size)
    }

    var body: some View {
        ZStack {
            arc(cpu, tint: GlassTone.blue, size: diameter)
            arc(gpu, tint: GlassTone.lilac, size: diameter * 0.78)
            arc(memory, tint: GlassTone.gold, size: diameter * 0.56)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(GlassNumber.text(power))
                    .font(.system(size: diameter * 0.145, weight: .bold, design: .rounded))
                Text("W")
                    .font(.system(size: diameter * 0.075, weight: .semibold))
            }
            .foregroundStyle(GlassTone.gold)
            .monospacedDigit()
        }
        .frame(width: diameter, height: diameter)
    }
}

private struct GlassSparkline: View {
    let values: [Double]
    var tint: Color = GlassTone.gold

    private func point(_ index: Int, size: CGSize) -> CGPoint {
        let low = values.min() ?? 0
        let high = values.max() ?? 1
        let span = max(high - low, 0.5)
        let x = size.width * CGFloat(index) / CGFloat(max(values.count - 1, 1))
        let fraction = CGFloat((values[index] - low) / span)
        return CGPoint(x: x, y: 6 + (size.height - 12) * (1 - fraction))
    }

    private func curve(_ size: CGSize) -> Path {
        Path { path in
            guard values.count > 1 else { return }
            for index in values.indices {
                let p = point(index, size: size)
                if index == 0 { path.move(to: p) }
                else { path.addLine(to: p) }
            }
        }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Path { path in
                    let y = proxy.size.height * 0.78
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                }
                .stroke(.white.opacity(0.09), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))

                if values.count > 1 {
                    curve(proxy.size)
                        .stroke(tint.opacity(0.58),
                                style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                        .blur(radius: 4)
                    curve(proxy.size)
                        .stroke(tint, style: StrokeStyle(lineWidth: 2.4, lineCap: .round,
                                                        lineJoin: .round))
                    if let lastIndex = values.indices.last {
                        Circle().fill(.white)
                            .frame(width: 7, height: 7)
                            .shadow(color: tint.opacity(0.9), radius: 6)
                            .position(point(lastIndex, size: proxy.size))
                    }
                } else {
                    Text("等待功率趋势")
                        .font(.caption2)
                        .foregroundStyle(GlassTone.secondary)
                }
            }
        }
        .accessibilityLabel("最近一次功率趋势")
    }
}

private struct GlassCoreBars: View {
    let values: [Double]
    let tierNames: [String]
    let barHeight: CGFloat

    private func tint(at index: Int) -> Color {
        guard tierNames.indices.contains(index) else { return GlassTone.blue }
        let tier = tierNames[index]
        if tier == "超级核" { return GlassTone.gold }
        if tier == "能效核" { return GlassTone.mint }
        if tier == "性能核" { return GlassTone.blue }
        return GlassTone.blue
    }

    var body: some View {
        if values.isEmpty {
            Text("打开 ChipBar 获取逐核心读数")
                .font(.caption2)
                .foregroundStyle(GlassTone.secondary)
                .frame(maxWidth: .infinity, minHeight: barHeight, alignment: .center)
        } else {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(values.prefix(32).enumerated()), id: \.offset) { item in
                    let tint = tint(at: item.offset)
                    ZStack(alignment: .bottom) {
                        Capsule().fill(.white.opacity(0.09))
                        Capsule().fill(LinearGradient(colors: [tint.opacity(0.75), tint],
                                                      startPoint: .bottom, endPoint: .top))
                            .frame(height: max(3, barHeight * CGFloat(min(100, max(0, item.element))) / 100))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: barHeight)
        }
    }
}

private struct GlassStorageRow: View {
    let name: String
    let freeGB: Double?
    let totalGB: Double?
    let readMB: Double?
    let writeMB: Double?
    var dense: Bool = false
    var color: Color = GlassTone.blue

    private var used: Double? {
        guard let freeGB, let totalGB, totalGB > 0 else { return nil }
        return min(1, max(0, 1 - freeGB / totalGB))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: dense ? 3 : 5) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(name)
                    .font(.system(size: dense ? 10 : 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 0)
                Text(GlassNumber.capacity(freeGB))
                    .font(.system(size: dense ? 10 : 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit().lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let used {
                    Text("已用 \(Int(used * 100))%")
                        .font(.system(size: 9))
                        .foregroundStyle(GlassTone.secondary)
                        .lineLimit(1)
                }
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.13))
                    Capsule()
                        .fill(LinearGradient(colors: [color, color.opacity(0.55)],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: proxy.size.width * CGFloat(used ?? 0))
                }
            }
            .frame(height: dense ? 5 : 7)
            if !dense {
                Text("读 \(GlassNumber.text(readMB)) · 写 \(GlassNumber.text(writeMB)) MB/s")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(GlassTone.secondary)
                    .lineLimit(1)
                    .monospacedDigit()
            }
        }
    }
}

private struct GlassValuePill: View {
    let icon: String
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon).foregroundStyle(tint)
                .font(.system(size: 10))
            Text(label)
                .foregroundStyle(GlassTone.secondary)
                .font(.system(size: 10))
            Spacer(minLength: 0)
            Text(value)
                .foregroundStyle(.white)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 25)
        .background(.white.opacity(0.075),
                    in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).strokeBorder(.white.opacity(0.10), lineWidth: 0.7))
    }
}

private struct ChipBarWidgetContent: View {
    let entry: ChipBarWidgetEntry
    let tile: ChipBarWidgetTile

    @Environment(\.widgetFamily) private var family

    private var isFresh: Bool { !entry.telemetry.stale(at: entry.date) }
    private var data: WidgetTelemetry { entry.telemetry }
    private var history: [Double] { isFresh ? data.values("powerHistory") : [] }

    private func value(_ key: String) -> Double? {
        isFresh ? data.number(key) : nil
    }
    private func text(_ key: String, digits: Int = 1) -> String {
        GlassNumber.text(value(key), digits: digits)
    }
    private var gpu: Double? { value("gpuUsage") }
    private var cpu: Double? { value("cpuUsage") }
    private var memory: Double? { value("ramPercentage") }
    private var chip: Double? { value("chip") }
    private var chipLabel: String { isFresh ? data.label("chipName") ?? "Apple Silicon" : "Apple Silicon" }
    private var hasExternal: Bool { data.number("externalTotalGB") != nil && isFresh }

    @ViewBuilder var body: some View {
        Group {
            switch family {
            case .systemLarge: largeWidget
            case .systemMedium: mediumWidget
            default: smallWidget
            }
        }
        .padding(family == .systemSmall ? 12 : 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .modifier(GlassWidgetBackground(purple: family == .systemLarge ||
                                        (tile == .overview && family == .systemSmall)))
    }

    private var brandHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(GlassTone.gold)
                .frame(width: 29, height: 29)
                .background(GlassTone.gold.opacity(0.11),
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(GlassTone.gold.opacity(0.5), lineWidth: 1))
            VStack(alignment: .leading, spacing: 1) {
                Text(tile == .overview || tile == .powerTrend ? "ChipBar" : tile.title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white).lineLimit(1)
                Text(chipLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(GlassTone.secondary)
                    .lineLimit(1).minimumScaleFactor(0.75)
            }
            Spacer(minLength: 4)
            HStack(spacing: 4) {
                Circle()
                    .fill(isFresh ? GlassTone.mint : .orange)
                    .frame(width: 6, height: 6)
                Text(isFresh ? "已同步" : "待刷新")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(isFresh ? GlassTone.mint : GlassTone.secondary)
            }
            .padding(.horizontal, 7).padding(.vertical, 5)
            .background(.white.opacity(0.08), in: Capsule())
        }
    }

    private var powerHero: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("芯片总功率")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(GlassTone.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(text("chip"))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(GlassTone.gold)
                Text("W")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(GlassTone.secondary)
            }
            .lineLimit(1).minimumScaleFactor(0.7)
            .monospacedDigit()
            Text("均值 \(text("averagePower")) W · 峰值 \(text("peakPower")) W")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(GlassTone.secondary)
                .lineLimit(1).minimumScaleFactor(0.75)
        }
    }

    private var triple: GlassTripleRings {
        GlassTripleRings(cpu: cpu, gpu: gpu, memory: memory,
                         cpuPower: value("cpuPower"), gpuPower: value("gpuPower"),
                         memoryUsed: value("ramUsed"), compact: false)
    }

    private var compactTriple: GlassTripleRings {
        GlassTripleRings(cpu: cpu, gpu: gpu, memory: memory,
                         cpuPower: value("cpuPower"), gpuPower: value("gpuPower"),
                         memoryUsed: value("ramUsed"), compact: true)
    }

    private var accessoryPills: some View {
        HStack(spacing: 5) {
            GlassValuePill(icon: "fanblades", label: "风扇",
                           value: text("fanRPM", digits: 0), tint: GlassTone.cyan)
            GlassValuePill(icon: "sparkle", label: "ANE",
                           value: text("anePower") + "W", tint: GlassTone.lilac)
            GlassValuePill(icon: "bolt", label: "内部",
                           value: text("internalPower") + "W", tint: GlassTone.gold)
        }
    }

    private var largeWidget: some View {
        VStack(alignment: .leading, spacing: 7) {
            brandHeader
            HStack(alignment: .bottom, spacing: 6) {
                powerHero
                    .frame(maxWidth: .infinity, alignment: .leading)
                GlassSparkline(values: history)
                    .frame(maxWidth: .infinity).frame(height: 60)
            }
            Rectangle().fill(.white.opacity(0.15)).frame(height: 0.6)
            triple
            HStack(spacing: 6) {
                Text("CPU 各核心")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                let count = isFresh ? data.values("coreUsage", limit: 64).count : 0
                Text(count == 0 ? "等待读取" : "\(count) 个核心")
                    .font(.system(size: 9))
                    .foregroundStyle(GlassTone.secondary)
            }
            GlassCoreBars(values: isFresh ? data.values("coreUsage", limit: 64) : [],
                          tierNames: isFresh ? data.allNames("coreTiers") : [],
                          barHeight: 23)
            GlassStorageRow(name: "Macintosh HD",
                            freeGB: value("storageFreeGB"),
                            totalGB: value("storageTotalGB"),
                            readMB: value("storageReadMB"),
                            writeMB: value("storageWriteMB"),
                            dense: true, color: GlassTone.blue)
            if hasExternal {
                GlassStorageRow(name: data.label("externalName") ?? "外置磁盘",
                                freeGB: value("externalFreeGB"),
                                totalGB: value("externalTotalGB"),
                                readMB: value("externalReadMB"),
                                writeMB: value("externalWriteMB"),
                                dense: true, color: GlassTone.mint)
            }
            Spacer(minLength: 0)
            accessoryPills
        }
        .foregroundStyle(.white)
    }

    private var mediumWidget: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: tile.symbol)
                    .foregroundStyle(GlassTone.gold)
                Text(tile == .overview ? "ChipBar · 芯片监控" : tile.title)
                    .fontWeight(.bold)
                    .lineLimit(1)
                Spacer(minLength: 3)
                if let timestamp = data.sampledAt {
                    Text(timestamp, style: .time)
                        .foregroundStyle(GlassTone.secondary)
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.white)

            if tile == .storage {
                GlassStorageRow(name: "Macintosh HD", freeGB: value("storageFreeGB"),
                                totalGB: value("storageTotalGB"),
                                readMB: value("storageReadMB"),
                                writeMB: value("storageWriteMB"),
                                dense: false)
                if hasExternal {
                    GlassStorageRow(name: data.label("externalName") ?? "外置磁盘",
                                    freeGB: value("externalFreeGB"),
                                    totalGB: value("externalTotalGB"),
                                    readMB: value("externalReadMB"),
                                    writeMB: value("externalWriteMB"),
                                    dense: true, color: GlassTone.mint)
                }
            } else if tile == .applications {
                applicationRows(limit: 3)
            } else if tile == .cpuCores {
                HStack {
                    Text("\(isFresh ? data.values("coreUsage", limit: 64).count : 0) 个逻辑核心")
                    Spacer()
                    Text("CPU \(text("cpuUsage", digits: 0))%")
                }.font(.caption).foregroundStyle(GlassTone.secondary)
                GlassCoreBars(values: isFresh ? data.values("coreUsage", limit: 64) : [],
                              tierNames: isFresh ? data.allNames("coreTiers") : [],
                              barHeight: 65)
            } else if tile == .cpu || tile == .gpu || tile == .memory {
                HStack(spacing: 16) {
                    GlassMetricRing(value: tile == .cpu ? cpu : tile == .gpu ? gpu : memory,
                                    tint: tile == .cpu ? GlassTone.blue :
                                        tile == .gpu ? GlassTone.lilac : GlassTone.gold,
                                    diameter: 92)
                    VStack(alignment: .leading, spacing: 10) {
                        Text(tile.title)
                            .foregroundStyle(GlassTone.secondary).font(.caption)
                        Text(tile == .memory
                             ? GlassNumber.capacity(value("ramUsed"))
                             : text(tile == .cpu ? "cpuPower" : "gpuPower") + " W")
                            .font(.system(size: 25, weight: .bold, design: .rounded))
                            .foregroundStyle(.white).monospacedDigit()
                        Text(tile == .memory
                             ? "总内存 " + GlassNumber.capacity(value("ramTotal"))
                             : "温度 " + text(tile == .cpu ? "cpuTemperature" : "gpuTemperature") + "°C")
                            .font(.caption).foregroundStyle(GlassTone.secondary)
                    }
                    Spacer(minLength: 0)
                }
            } else if tile == .fan || tile == .ane || tile == .powerSupply {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(text(tile == .fan ? "fanRPM" :
                                  tile == .ane ? "anePower" : "internalPower",
                                  digits: tile == .fan ? 0 : 1))
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                            .foregroundStyle(GlassTone.gold).monospacedDigit()
                        Text(tile == .fan ? "RPM · 风扇转速" :
                             tile == .ane ? "W · Neural Engine" : "W · 内部 DC 功率")
                            .foregroundStyle(GlassTone.secondary).font(.caption)
                    }
                    Spacer()
                    GlassConcentricRings(power: chip, cpu: cpu, gpu: gpu, memory: memory,
                                         diameter: 100)
                }
            } else {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("芯片总功率")
                            .font(.system(size: 10)).foregroundStyle(GlassTone.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(text("chip"))
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                            Text("W").font(.system(size: 14))
                        }
                        .foregroundStyle(GlassTone.gold).monospacedDigit()
                        Text("均值 \(text("averagePower")) W")
                            .font(.system(size: 9)).foregroundStyle(GlassTone.secondary)
                        GlassSparkline(values: history)
                            .frame(height: 26)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    compactTriple
                        .frame(maxWidth: .infinity)
                }
            }
            Spacer(minLength: 0)
            if tile == .overview || tile == .powerTrend {
                accessoryPills
            }
        }
        .foregroundStyle(.white)
    }

    @ViewBuilder private var smallWidget: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: tile.symbol)
                    .foregroundStyle(GlassTone.gold)
                Text(tile == .overview ? "ChipBar" : tile.title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white).lineLimit(1)
                Spacer(minLength: 0)
            }
            if tile == .overview {
                Spacer(minLength: 0)
                GlassConcentricRings(power: chip, cpu: cpu, gpu: gpu,
                                     memory: memory, diameter: 92)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    legend("CPU", cpu, GlassTone.blue)
                    legend("GPU", gpu, GlassTone.lilac)
                    legend("内存", memory, GlassTone.gold)
                }
            } else if tile == .cpu || tile == .gpu || tile == .memory {
                Spacer(minLength: 0)
                GlassMetricRing(value: tile == .cpu ? cpu : tile == .gpu ? gpu : memory,
                                tint: tile == .cpu ? GlassTone.blue :
                                    tile == .gpu ? GlassTone.lilac : GlassTone.gold,
                                diameter: 88)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
                Text(tile == .memory
                     ? GlassNumber.capacity(value("ramUsed"))
                     : text(tile == .cpu ? "cpuPower" : "gpuPower") + " W")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white).monospacedDigit()
                    .frame(maxWidth: .infinity)
            } else if tile == .storage {
                Spacer(minLength: 1)
                GlassStorageRow(name: "Macintosh HD", freeGB: value("storageFreeGB"),
                                totalGB: value("storageTotalGB"),
                                readMB: value("storageReadMB"), writeMB: value("storageWriteMB"),
                                dense: true)
                if hasExternal {
                    GlassStorageRow(name: data.label("externalName") ?? "外置磁盘",
                                    freeGB: value("externalFreeGB"),
                                    totalGB: value("externalTotalGB"),
                                    readMB: value("externalReadMB"), writeMB: value("externalWriteMB"),
                                    dense: true, color: GlassTone.mint)
                }
                Spacer(minLength: 0)
            } else if tile == .cpuCores {
                Spacer(minLength: 0)
                GlassCoreBars(values: isFresh ? data.values("coreUsage", limit: 64) : [],
                              tierNames: isFresh ? data.allNames("coreTiers") : [],
                              barHeight: 70)
                Spacer(minLength: 0)
                Text("逐核心占用")
                    .foregroundStyle(GlassTone.secondary).font(.caption2)
            } else if tile == .applications {
                applicationRows(limit: 2)
                Spacer(minLength: 0)
            } else if tile == .powerTrend {
                Text(text("chip") + " W")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(GlassTone.gold).monospacedDigit()
                GlassSparkline(values: history).frame(height: 65)
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                Text(text(tile == .fan ? "fanRPM" :
                          tile == .ane ? "anePower" : "internalPower",
                          digits: tile == .fan ? 0 : 1))
                    .font(.system(size: 33, weight: .bold, design: .rounded))
                    .foregroundStyle(GlassTone.gold)
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                Text(tile == .fan ? "RPM" : "W")
                    .foregroundStyle(GlassTone.secondary).font(.caption)
                Spacer(minLength: 0)
                GlassSparkline(values: history).frame(height: 24)
            }
            HStack(spacing: 4) {
                Circle().fill(isFresh ? GlassTone.mint : .orange)
                    .frame(width: 5, height: 5)
                Text(isFresh ? "最近一次监测" : "等待新数据")
                    .foregroundStyle(GlassTone.secondary)
                    .font(.system(size: 8))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        }
        .foregroundStyle(.white)
    }

    private func legend(_ label: String, _ number: Double?, _ tint: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(tint).frame(width: 5, height: 5)
            Text(GlassNumber.text(number, digits: 0) + "%")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel(label)
    }

    private func applicationRows(limit: Int) -> some View {
        let names = isFresh ? data.names("applicationNames", limit: limit) : []
        let cpu = isFresh ? data.values("applicationCPU", limit: limit) : []
        return VStack(alignment: .leading, spacing: 8) {
            if names.isEmpty {
                Text("打开 ChipBar 获取应用占用")
                    .font(.caption)
                    .foregroundStyle(GlassTone.secondary)
            } else {
                ForEach(Array(names.enumerated()), id: \.offset) { item in
                    HStack {
                        Text(item.element).lineLimit(1)
                        Spacer(minLength: 0)
                        if cpu.indices.contains(item.offset) {
                            Text(String(format: "%.0f%%", cpu[item.offset]))
                                .monospacedDigit()
                        }
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                }
            }
        }
    }
}

@main
struct ChipBarWidgets: WidgetBundle {
    @WidgetBundleBuilder
    var body: some Widget {
        ChipBarTelemetryWidget<OverviewWidgetModule>()
        ChipBarTelemetryWidget<PowerTrendWidgetModule>()
        ChipBarTelemetryWidget<CPUWidgetModule>()
        ChipBarTelemetryWidget<GPUWidgetModule>()
        ChipBarTelemetryWidget<MemoryWidgetModule>()
        ChipBarTelemetryWidget<CPUCoresWidgetModule>()
        ChipBarTelemetryWidget<FanWidgetModule>()
        ChipBarTelemetryWidget<ANEWidgetModule>()
        ChipBarTelemetryWidget<StorageWidgetModule>()
        ChipBarTelemetryWidget<PowerSupplyWidgetModule>()
        ChipBarTelemetryWidget<ApplicationsWidgetModule>()
    }
}
