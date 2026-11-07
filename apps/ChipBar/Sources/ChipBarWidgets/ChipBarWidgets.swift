import Foundation
import SwiftUI
import WidgetKit

/// All ten ChipBar dashboard modules are independent, selectable widgets in
/// the macOS desktop / Notification Center widget gallery. The system owns
/// placement, sizing and update budgets.
private enum ChipBarWidgetTile: String, CaseIterable {
    case powerTrend, cpu, gpu, memory, cpuCores, fan, ane, storage, powerSupply, applications

    var title: String {
        switch self {
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

    var symbol: String {
        switch self {
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
        .configurationDisplayName("ChipBar · \(tile.title)")
        .description("在桌面或通知中心查看 \(tile.title) 的最近一次监测快照。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct ChipBarWidgetContent: View {
    let entry: ChipBarWidgetEntry
    let tile: ChipBarWidgetTile

    @Environment(\.widgetFamily) private var family

    private var stale: Bool { entry.telemetry.stale(at: entry.date) }
    private var teal: Color { Color(red: 0.23, green: 0.68, blue: 0.82) }

    private func formatted(_ value: Double?, digits: Int = 1) -> String {
        guard let value, !stale else { return "—" }
        return String(format: digits == 0 ? "%.0f" : "%.1f", value)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: tile.symbol).foregroundStyle(teal)
                Text(tile.title).fontWeight(.semibold).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "bolt.fill")
                    .foregroundStyle(.secondary).font(.caption2)
            }
            .font(.system(size: 12))

            tileDetails
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            HStack(spacing: 4) {
                Circle()
                    .fill(stale ? Color.orange : Color.green)
                    .frame(width: 5, height: 5)
                Text(stale ? "数据已过期 · 打开 ChipBar" : "最近一次采样")
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let timestamp = entry.telemetry.sampledAt {
                    Text(timestamp, style: .time)
                }
            }
            .font(.system(size: 9))
            .foregroundStyle(.secondary)
        }
        .padding(13)
        .modifier(ChipBarWidgetBackground())
    }

    @ViewBuilder private var tileDetails: some View {
        let data = entry.telemetry
        switch tile {
        case .powerTrend:
            metricText(formatted(data.number("chip")) + " W")
            Sparkline(values: stale ? [] : data.values("powerHistory"), tint: .orange)
                .frame(height: family == .systemSmall ? 42 : 75)
        case .cpu:
            metricText(formatted(data.number("cpuUsage"), digits: 0) + "%")
            Text("功率 " + formatted(data.number("cpuPower")) + " W")
                .foregroundStyle(.secondary).font(.caption)
            ProgressView(value: stale ? 0 : min(100, data.number("cpuUsage") ?? 0),
                         total: 100).tint(.blue)
        case .gpu:
            metricText(formatted(data.number("gpuUsage"), digits: 0) + "%")
            Text("功率 " + formatted(data.number("gpuPower")) + " W")
                .foregroundStyle(.secondary).font(.caption)
            ProgressView(value: stale ? 0 : min(100, data.number("gpuUsage") ?? 0),
                         total: 100).tint(.purple)
        case .memory:
            metricText(formatted(data.number("ramPercentage"), digits: 0) + "%")
            Text(formatted(data.number("ramUsed")) + " / " +
                 formatted(data.number("ramTotal")) + " GB")
                .font(.caption).foregroundStyle(.secondary)
            ProgressView(value: stale ? 0 : min(100, data.number("ramPercentage") ?? 0),
                         total: 100).tint(.mint)
        case .cpuCores:
            let cores = stale ? [] : data.values("coreUsage", limit: 64)
            Text(cores.isEmpty ? "暂无逐核心数据" : "\(cores.count) 个逻辑核心")
                .font(.caption).foregroundStyle(.secondary)
            CoreBars(values: cores).frame(height: family == .systemSmall ? 45 : 88)
        case .fan:
            metricText(formatted(data.number("fanRPM"), digits: 0) + " RPM")
            Text("当前风扇转速").font(.caption).foregroundStyle(.secondary)
        case .ane:
            metricText(formatted(data.number("anePower")) + " W")
            Text("Apple Neural Engine").font(.caption).foregroundStyle(.secondary)
        case .storage:
            metricText(formatted(data.number("storageFreeGB"), digits: 0) + " GB")
            Text("可用 / 总计 " + formatted(data.number("storageTotalGB"), digits: 0) + " GB")
                .font(.caption).foregroundStyle(.secondary)
            if !stale, let free = data.number("storageFreeGB"),
               let total = data.number("storageTotalGB"), total > 0 {
                ProgressView(value: max(0, min(1, 1 - free / total)))
                    .tint(teal)
            }
        case .powerSupply:
            metricText(formatted(data.number("internalPower")) + " W")
            Text("内部 DC 功率 · 非插座 AC")
                .font(.caption).foregroundStyle(.secondary)
        case .applications:
            let names = stale ? [] : data.names("applicationNames")
            let values = stale ? [] : data.values("applicationCPU", limit: 3)
            if names.isEmpty {
                Text("暂无应用占用快照").foregroundStyle(.secondary).font(.caption)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(names.enumerated()), id: \.offset) { item in
                        HStack {
                            Text(item.element).lineLimit(1)
                            Spacer()
                            if item.offset < values.count {
                                Text(String(format: "%.0f%%", values[item.offset]))
                                    .monospacedDigit()
                            }
                        }
                        .font(.caption)
                    }
                }
            }
        }
    }

    private func metricText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: family == .systemSmall ? 23 : 32,
                          weight: .semibold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.65)
    }
}

private struct Sparkline: View {
    let values: [Double]
    let tint: Color

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                guard values.count > 1 else { return }
                let range = max(1, (values.max() ?? 1) - (values.min() ?? 0))
                let low = values.min() ?? 0
                let width = geometry.size.width
                let height = geometry.size.height
                for (index, value) in values.enumerated() {
                    let point = CGPoint(
                        x: width * CGFloat(index) / CGFloat(values.count - 1),
                        y: height - CGFloat((value - low) / range) * height)
                    if index == 0 { path.move(to: point) }
                    else { path.addLine(to: point) }
                }
            }
            .stroke(tint, style: StrokeStyle(lineWidth: 2.4, lineCap: .round,
                                             lineJoin: .round))
        }
    }
}

private struct CoreBars: View {
    let values: [Double]
    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(values.enumerated()), id: \.offset) { item in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.blue.opacity(0.85))
                        .frame(height: max(3, geometry.size.height * CGFloat(min(100, item.element)) / 100))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }
}

private struct ChipBarWidgetBackground: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.containerBackground(.thinMaterial, for: .widget)
        } else {
            content.background(.regularMaterial)
        }
    }
}

@main
struct ChipBarWidgets: WidgetBundle {
    @WidgetBundleBuilder
    var body: some Widget {
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
