import Foundation
import SwiftUI
import WidgetKit

/// Exactly the two designs in the supplied reference: a dashboard in three
/// system sizes, and the separate compact storage card. Removing registered
/// kinds also removes the old per-CPU/GPU/memory entries from WidgetKit gallery.
private enum ChipBarWidgetTile: String {
    case overview, storage

    var title: String {
        switch self {
        case .overview: return "ChipBar 仪表盘"
        case .storage: return "储存空间"
        }
    }

    /// LocalizedStringKey values must be compile-time literals. Formatting
    /// gallery descriptions dynamically can crash chronod's descriptor query.
    var galleryTitle: LocalizedStringKey {
        switch self {
        case .overview: return "ChipBar · 仪表盘"
        case .storage: return "ChipBar · 储存空间"
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "waveform.path.ecg.rectangle"
        case .storage: return "internaldrive"
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
        // The host refreshes its file more frequently; request a new view
        // roughly every two minutes, but WidgetKit may coalesce or defer it.
        // Never wake a separate SMC polling process from the extension.
        completion(Timeline(entries: [entry], policy: .after(date.addingTimeInterval(2 * 60))))
    }
}

// Separate zero-argument Widget types are required for macOS to restore
// independently placed instances. The gallery exposes only these two kinds.
private protocol ChipBarWidgetModule {
    static var tile: ChipBarWidgetTile { get }
}
private enum OverviewWidgetModule: ChipBarWidgetModule {
    static let tile: ChipBarWidgetTile = .overview
}
private enum StorageWidgetModule: ChipBarWidgetModule {
    static let tile: ChipBarWidgetTile = .storage
}

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
        .supportedFamilies(tile == .storage
                           ? [.systemSmall]
                           : [.systemSmall, .systemMedium, .systemLarge])
    }
}


private enum GlassTone {
    static let blue = Color(red: 0.53, green: 0.74, blue: 0.97)
    static let lilac = Color(red: 0.80, green: 0.72, blue: 0.96)
    static let gold = Color(red: 0.98, green: 0.83, blue: 0.47)
    static let mint = Color(red: 0.49, green: 0.86, blue: 0.80)
    static let cyan = Color(red: 0.42, green: 0.77, blue: 0.91)
    static let ink = Color.white
    static let secondary = Color(red: 0.77, green: 0.81, blue: 0.90)
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
                    ? [Color(red: 0.28, green: 0.25, blue: 0.52),
                       Color(red: 0.14, green: 0.15, blue: 0.32),
                       Color(red: 0.23, green: 0.14, blue: 0.30)]
                    : [Color(red: 0.10, green: 0.17, blue: 0.29),
                       Color(red: 0.11, green: 0.22, blue: 0.36),
                       Color(red: 0.13, green: 0.31, blue: 0.43)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(
                colors: purple
                    ? [Color(red: 0.56, green: 0.33, blue: 0.56).opacity(0.24), .clear]
                    : [GlassTone.cyan.opacity(0.15), .clear],
                center: .bottomTrailing,
                startRadius: 3, endRadius: 340)
            RadialGradient(colors: [GlassTone.lilac.opacity(purple ? 0.11 : 0.04), .clear],
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
                .shadow(color: tint.opacity(0.42), radius: diameter * 0.07)
            Text(GlassNumber.text(value, digits: 0) + "%")
                .font(.system(size: diameter * 0.22, weight: .bold, design: .rounded))
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
        .accessibilityElement(children: .combine)
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
                .shadow(color: tint.opacity(0.33), radius: 4)
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
                        .stroke(tint.opacity(0.28),
                                style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                        .blur(radius: 4)
                    curve(proxy.size)
                        .stroke(tint, style: StrokeStyle(lineWidth: 2.4, lineCap: .round,
                                                        lineJoin: .round))
                    if let lastIndex = values.indices.last {
                        Circle().fill(.white)
                            .frame(width: 7, height: 7)
                            .shadow(color: tint.opacity(0.45), radius: 4)
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
            Text("核心数据采集中…")
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
    var showsRates: Bool = true
    var color: Color = GlassTone.blue

    private var used: Double? {
        guard let freeGB, let totalGB, totalGB > 0 else { return nil }
        return min(1, max(0, 1 - freeGB / totalGB))
    }

    private var usedLabel: String {
        guard let used else { return "—" }
        return "已用 \(Int(used * 100))%"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: dense ? 3 : 4) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(name)
                    .font(.system(size: dense ? 9 : 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1).truncationMode(.middle)
                    .minimumScaleFactor(0.64)
                    .layoutPriority(-1)
                Spacer(minLength: 0)
                Text(GlassNumber.capacity(freeGB))
                    .font(.system(size: dense ? 9 : 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.63)
                    .layoutPriority(2)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.13))
                    Capsule()
                        .fill(LinearGradient(colors: [color, color.opacity(0.67)],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: proxy.size.width * CGFloat(used ?? 0))
                }
            }
            .frame(height: dense ? 5 : 6)
            HStack(spacing: 4) {
                Text(usedLabel)
                    .lineLimit(1)
                    .layoutPriority(1)
                Spacer(minLength: 0)
                if showsRates {
                    Text("读 \(GlassNumber.text(readMB)) · 写 \(GlassNumber.text(writeMB)) MB/s")
                        .lineLimit(1)
                        .minimumScaleFactor(0.56)
                        .monospacedDigit()
                }
            }
            .font(.system(size: dense ? 8 : 9, weight: .medium))
            .foregroundStyle(GlassTone.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
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
                .font(.system(size: 9))
            Spacer(minLength: 0)
            Text(value)
                .foregroundStyle(.white)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.55)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, minHeight: 22)
        .background(.white.opacity(0.075),
                    in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).strokeBorder(.white.opacity(0.10), lineWidth: 0.7))
    }
}

private struct ChipBarWidgetContent: View {
    let entry: ChipBarWidgetEntry
    let tile: ChipBarWidgetTile

    @Environment(\.widgetFamily) private var family

    private var fresh: Bool { !entry.telemetry.stale(at: entry.date) }
    private var data: WidgetTelemetry { entry.telemetry }
    // Never erase the last genuine readings simply because the system has
    // deferred the next widget timeline. The status reports snapshot age;
    // a dash means no hardware reading was provided at all.
    private var history: [Double] { data.values("powerHistory") }
    private func value(_ key: String) -> Double? { data.number(key) }
    private func text(_ key: String, digits: Int = 1) -> String {
        GlassNumber.text(value(key), digits: digits)
    }
    private var cpu: Double? { value("cpuUsage") }
    private var gpu: Double? { value("gpuUsage") }
    private var memory: Double? { value("ramPercentage") }
    private var chip: Double? { value("chip") }
    private var chipLabel: String {
        data.label("chipName") ?? "Apple Silicon"
    }
    private var hasExternal: Bool { data.number("externalTotalGB") != nil }

    var body: some View {
        GeometryReader { geometry in
            Group {
                switch family {
                case .systemLarge:
                    dashboardLarge(in: geometry.size)
                case .systemMedium:
                    dashboardMedium(in: geometry.size)
                default:
                    dashboardSmall(in: geometry.size)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height,
                   alignment: .topLeading)
        }
        // WidgetKit provides its own margins. Keep additional insets modest
        // so the large dashboard and small storage text never spill out.
        .padding(family == .systemSmall ? 8 : 10)
        .modifier(GlassWidgetBackground(purple: family == .systemLarge))
    }

    private var status: some View {
        HStack(spacing: 4) {
            Circle().fill(fresh ? GlassTone.mint : .orange)
                .frame(width: 5, height: 5)
            Text(fresh ? "快照" : "旧快照")
                .lineLimit(1)
                .foregroundStyle(GlassTone.secondary)
        }
        .font(.system(size: 8, weight: .medium))
        .accessibilityLabel(fresh ? "最近一次监测已同步" : "监测数据等待刷新")
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: tile == .storage ? "internaldrive" : "waveform.path.ecg")
                .foregroundStyle(GlassTone.gold)
                .font(.system(size: 12))
                .frame(width: 21, height: 21)
                .background(.white.opacity(0.07),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(tile == .overview ? "ChipBar" : "储存空间")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.80)
                if tile == .overview {
                    Text(chipLabel)
                        .font(.system(size: 9))
                        .foregroundStyle(GlassTone.secondary)
                        .lineLimit(1).minimumScaleFactor(0.70)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            status
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(height: 26)
    }

    private var powerHero: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("芯片总功率")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(GlassTone.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(text("chip"))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(GlassTone.gold)
                Text("W").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(GlassTone.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.58)
            .monospacedDigit()
            Text("均 \(text("averagePower")) · 峰 \(text("peakPower")) W")
                .font(.system(size: 9))
                .foregroundStyle(GlassTone.secondary)
                .lineLimit(1).minimumScaleFactor(0.64)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var triple: GlassTripleRings {
        GlassTripleRings(cpu: cpu, gpu: gpu, memory: memory,
                         cpuPower: value("cpuPower"),
                         gpuPower: value("gpuPower"),
                         memoryUsed: value("ramUsed"), compact: false)
    }

    private var compactTriple: GlassTripleRings {
        GlassTripleRings(cpu: cpu, gpu: gpu, memory: memory,
                         cpuPower: value("cpuPower"),
                         gpuPower: value("gpuPower"),
                         memoryUsed: value("ramUsed"), compact: true)
    }

    private var accessoryPills: some View {
        HStack(spacing: 4) {
            GlassValuePill(icon: "fanblades", label: "风扇",
                           value: text("fanRPM", digits: 0), tint: GlassTone.cyan)
            GlassValuePill(icon: "sparkle", label: "ANE",
                           value: text("anePower") + "W", tint: GlassTone.lilac)
            GlassValuePill(icon: "bolt", label: "内部",
                           value: text("internalPower") + "W", tint: GlassTone.gold)
        }
    }

    private var internalDisk: some View {
        GlassStorageRow(name: "Macintosh HD",
                        freeGB: value("storageFreeGB"),
                        totalGB: value("storageTotalGB"),
                        readMB: value("storageReadMB"),
                        writeMB: value("storageWriteMB"),
                        dense: true, color: GlassTone.blue)
    }

    private var externalDisk: some View {
        GlassStorageRow(name: data.label("externalName") ?? "外置磁盘",
                        freeGB: value("externalFreeGB"),
                        totalGB: value("externalTotalGB"),
                        readMB: value("externalReadMB"),
                        writeMB: value("externalWriteMB"),
                        dense: true, color: GlassTone.mint)
    }

    /// Large corresponds to the left-hand purple high-density composition in
    /// the reference. Avoid a variable-height vertical disk stack: a mounted
    /// USB drive must never push the bottom pills outside the widget bounds.
    private func dashboardLarge(in size: CGSize) -> some View {
        let tight = size.height < 330
        let spacing: CGFloat = tight ? 3 : 5
        return VStack(alignment: .leading, spacing: spacing) {
            header
            HStack(alignment: .bottom, spacing: 8) {
                powerHero
                    .frame(maxWidth: .infinity, alignment: .leading)
                GlassSparkline(values: history)
                    .frame(maxWidth: .infinity)
                    .frame(height: tight ? 38 : 52)
            }
            Rectangle().fill(.white.opacity(0.13)).frame(height: 0.6)
            if tight { compactTriple } else { triple }
            HStack(spacing: 5) {
                Text("CPU 各核心")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
                let count = data.values("coreUsage", limit: 64).count
                Text(count == 0 ? "采集中…" : "\(count) 个核心")
                    .font(.system(size: 9))
                    .foregroundStyle(GlassTone.secondary)
                    .lineLimit(1)
            }
            GlassCoreBars(values: data.values("coreUsage", limit: 64),
                          tierNames: data.allNames("coreTiers"),
                          barHeight: tight ? 16 : 21)
            HStack(alignment: .top, spacing: 8) {
                internalDisk
                    .frame(maxWidth: .infinity)
                if hasExternal {
                    externalDisk
                        .frame(maxWidth: .infinity)
                }
            }
            Spacer(minLength: 0)
            accessoryPills
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .foregroundStyle(.white)
    }

    /// Medium is the horizontal navy card with warm power and three rings.
    private func dashboardMedium(in size: CGSize) -> some View {
        let tight = size.height < 145
        return VStack(alignment: .leading, spacing: tight ? 3 : 5) {
            HStack(spacing: 4) {
                Image(systemName: "waveform.path.ecg")
                    .foregroundStyle(GlassTone.gold)
                Text("ChipBar · 芯片总功率")
                    .fontWeight(.semibold)
                    .lineLimit(1).minimumScaleFactor(0.78)
                Spacer(minLength: 4)
                status
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundStyle(.white)
            .font(.system(size: 10))
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: tight ? 2 : 4) {
                    if tight {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(text("chip"))
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                            Text("W")
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(GlassTone.gold)
                        .lineLimit(1).minimumScaleFactor(0.58)
                        Text("均值 " + text("averagePower") + " W")
                            .font(.system(size: 8))
                            .foregroundStyle(GlassTone.secondary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    } else {
                        powerHero
                    }
                    GlassSparkline(values: history)
                        .frame(height: tight ? 21 : 25)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                compactTriple
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            Spacer(minLength: 0)
            accessoryPills
        }
        .foregroundStyle(.white)
    }

    /// Small overview mirrors the three concentric arcs in the screenshot,
    /// while small storage remains a completely separate gallery item.
    private func dashboardSmall(in size: CGSize) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: tile == .storage ? "internaldrive" :
                      "waveform.path.ecg")
                    .foregroundStyle(GlassTone.gold)
                Text(tile == .storage ? "储存空间" : "ChipBar")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 0)
                status
                    .fixedSize(horizontal: true, vertical: false)
            }
            if tile == .storage {
                Spacer(minLength: 0)
                internalDisk
                if hasExternal { externalDisk }
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                GlassConcentricRings(power: chip, cpu: cpu, gpu: gpu,
                                     memory: memory,
                                     diameter: min(88, max(62, size.height - 55)))
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
                HStack(spacing: 3) {
                    legend(cpu, GlassTone.blue)
                    legend(gpu, GlassTone.lilac)
                    legend(memory, GlassTone.gold)
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .foregroundStyle(.white)
    }

    private func legend(_ number: Double?, _ tint: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(tint).frame(width: 4, height: 4)
            Text(GlassNumber.text(number, digits: 0) + "%")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
        }
        .frame(maxWidth: .infinity)
    }
}

@main
struct ChipBarWidgets: WidgetBundle {
    @WidgetBundleBuilder
    var body: some Widget {
        ChipBarTelemetryWidget<OverviewWidgetModule>()
        ChipBarTelemetryWidget<StorageWidgetModule>()
    }
}
