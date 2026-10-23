import SwiftUI
import ChipBarCore

enum ApplicationResource: String, CaseIterable, Identifiable {
    case cpu = "CPU", gpu = "GPU", memory = "内存", ane = "ANE"
    var id: String { rawValue }
}

struct ApplicationUsageSection: View {
    @ObservedObject var monitor: Monitor
    @ObservedObject var state: DashboardState
    @StateObject private var activity = ApplicationActivityModel.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if #available(macOS 14.0, *) {
                disclosureButton.focusEffectDisabled()
            } else {
                disclosureButton
            }
            Picker("应用资源排行", selection: $state.applicationMetric) {
                ForEach(ApplicationResource.allCases) { Text($0.rawValue).tag($0) }
            }.labelsHidden().pickerStyle(.segmented)
            ranking.frame(height: 84 + 56 * state.applicationsExpansion, alignment: .topLeading).clipped()
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topLeading) {
                    Text(shortExplanation).opacity(1 - state.applicationsExpansion)
                    Text(explanation).opacity(state.applicationsExpansion)
                }
                .frame(height: 14 + 28 * state.applicationsExpansion, alignment: .topLeading).clipped()
                Text(activity.snapshot.map(samplingSummary) ?? "正在读取进程计数…")
                    .lineLimit(1).padding(.top, 8)
                    .opacity(state.applicationsExpansion)
                    .frame(height: 20 * state.applicationsExpansion, alignment: .topLeading).clipped()
            }.font(.caption2).foregroundStyle(.secondary)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(state.showApplications ? explanation : shortExplanation)
        }
        .task(id: "\(monitor.paused)-\(monitor.sleeping)-\(monitor.interval)") {
            guard !monitor.paused, !monitor.sleeping else { return }
            await activity.watch(interval: monitor.interval)
        }
    }

    private var disclosureButton: some View {
        Button { state.toggleApplications() } label: {
            HStack {
                Text("应用占用").font(.subheadline.weight(.medium))
                Spacer()
                Text(state.showApplications ? "收起" : "更多").font(.caption)
                Image(systemName: "chevron.down").font(.caption2)
                    .rotationEffect(.degrees(180 * state.applicationsExpansion))
            }.contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityLabel(state.showApplications ? "收起为前三名应用" : "查看前五名应用及指标说明")
    }

    @ViewBuilder private var ranking: some View {
        if monitor.paused || monitor.sleeping {
            message("应用占用采样已暂停", symbol: "pause.circle")
        } else if let snapshot = activity.snapshot {
            let rows = rankedRows(snapshot)
            if !rows.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        HStack(spacing: 8) {
                            Text("\(index + 1)").monospacedDigit()
                                .foregroundStyle(.secondary).frame(width: 16).accessibilityHidden(true)
                            Text(row.name).lineLimit(1).truncationMode(.middle)
                                .help("\(row.name) · 合并 \(row.processCount) 个进程；只统计可读取的计数器")
                            Spacer(minLength: 6)
                            Text(formatted(row)).monospacedDigit()
                                .foregroundStyle(.primary)
                        }.font(.callout).frame(height: 28)
                        .opacity(index < 3 ? 1 : state.applicationsExpansion)
                        .accessibilityElement(children: .combine)
                        .accessibilityHidden(!state.showApplications && index >= 3)
                    }
                }
            } else {
                message(emptyMessage(snapshot), symbol: "chart.bar.xaxis")
            }
        } else {
            message("正在读取应用占用…", symbol: "clock")
        }
    }

    private func rankedRows(_ snapshot: ActivitySnapshot) -> [ApplicationActivityRow] {
        Array(snapshot.rows.filter {
            (value($0) ?? -1) > (state.applicationMetric == .ane || state.applicationMetric == .memory ? 0 : -1)
        }
            .sorted {
                let lhs = value($0) ?? 0, rhs = value($1) ?? 0
                return lhs == rhs ? $0.id < $1.id : lhs > rhs
            }.prefix(5))
    }

    private func value(_ row: ApplicationActivityRow) -> Double? {
        switch state.applicationMetric {
        case .cpu: return row.cpuPercent
        case .gpu: return row.gpuPercent
        case .memory: return row.physicalBytes.map(Double.init)
        case .ane: return row.neuralBytes.map(Double.init)
        }
    }

    private func formatted(_ row: ApplicationActivityRow) -> String {
        guard let number = value(row) else { return "—" }
        switch state.applicationMetric {
        case .cpu, .gpu: return String(format: "%.1f%%", number)
        case .memory, .ane:
            return number >= 1_000_000_000
                ? String(format: "%.2f GB", number / 1_000_000_000)
                : String(format: "%.1f MB", number / 1_000_000)
        }
    }

    private func samplingSummary(_ snapshot: ActivitySnapshot) -> String {
        let detail: String
        switch state.applicationMetric {
        case .cpu: detail = "CPU 可读取 \(snapshot.readableCPUCount)/\(snapshot.processCount) 个进程"
        case .gpu: detail = "GPU 读取 \(snapshot.gpuClientCount) 个驱动客户端"
        case .memory: detail = "内存可读取 \(snapshot.readableMemoryCount)/\(snapshot.processCount) 个进程"
        case .ane: detail = snapshot.neuralSupported ? "ANE 内存计数可用" : "当前未提供 ANE 内存计数"
        }
        return "\(detail) · 每 \(max(2, monitor.interval / 1000)) 秒更新"
    }

    private func emptyMessage(_ snapshot: ActivitySnapshot) -> String {
        switch state.applicationMetric {
        case .cpu: return snapshot.readableCPUCount > 0 ? "正在建立 CPU 采样基线…" : "当前无法读取进程 CPU 计数器"
        case .gpu: return snapshot.gpuClientCount > 0 ? "正在建立 GPU 采样基线…" : "当前驱动未提供应用 GPU 时间"
        case .memory: return snapshot.readableMemoryCount > 0 ? "当前未观察到非零应用内存读数" : "当前无法读取应用内存"
        case .ane: return snapshot.neuralSupported ? "当前未观察到已记账的 ANE 内存" : "当前环境未提供应用 ANE 内存"
        }
    }

    private var explanation: String {
        switch state.applicationMetric {
        case .cpu: return "100% 表示占满一个逻辑核心，多核应用可超过100%。同一应用内的辅助进程合并统计。"
        case .gpu: return "驱动 GPU 时间 / 采样间隔，可超过100%；不等同于整机 GPU 利用率的分摊。共享服务单独显示。"
        case .memory: return "内存为各进程当前物理占用（Physical Footprint）合计，含可读取的应用辅助进程；与系统总内存占用不直接相加。"
        case .ane: return "此处为 ANE 记账内存，不是计算利用率。系统未提供逐应用 ANE 计算百分比；没有记账不代表未使用 ANE。"
        }
    }

    private var shortExplanation: String {
        switch state.applicationMetric {
        case .cpu: return "前三名 · 100% = 一个逻辑核心"
        case .gpu: return "前三名 · GPU 时间占比，可超过100%"
        case .memory: return "前三名 · 物理内存占用（MB / GB）"
        case .ane: return "前三名 · ANE 记账内存，非计算利用率"
        }
    }

    private func message(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .multilineTextAlignment(.center)
    }
}
