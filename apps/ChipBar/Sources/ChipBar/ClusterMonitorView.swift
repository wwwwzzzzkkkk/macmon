import AppKit
import SwiftUI
import ChipBarCore

/// Matches the compact, full-width home tile rather than adding a second
/// dashboard or disturbing the existing six-track tile arrangement.
struct ClusterOverviewTile: View {
    @ObservedObject private var cluster = ClusterMonitorService.shared
    let selected: Bool
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 10) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color(red: 0.22, green: 0.65, blue: 0.79))
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 3) {
                    Text("计算集群")
                        .font(.caption.weight(.semibold))
                    Text(cluster.enabled
                         ? "\(cluster.onlinePeers.count + 1) 台在线 · 只读监控"
                         : "未启用 · 点击配置双机监控")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "chevron.right" : "rectangle.on.rectangle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .frame(height: 54)
            .frame(maxWidth: .infinity)
            .glassTile(radius: 24, tint: selected ? .cyan.opacity(0.12) : nil,
                       interactive: true)
            .contentShape(RoundedRectangle(cornerRadius: 24))
        }
        .buttonStyle(ChipBarPressStyle())
        .accessibilityLabel("计算集群，只读监控")
    }
}

/// Read-only cluster panel. Deliberately no start/stop, shell, task-queue,
/// task-scheduler, or remote execution controls.
struct ClusterMonitorPanel: View {
    @ObservedObject private var cluster = ClusterMonitorService.shared
    @ObservedObject var monitor: Monitor
    let close: () -> Void
    private let accent = Color(red: 0.22, green: 0.65, blue: 0.79)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .foregroundStyle(accent)
                Text("计算集群").font(.headline)
                Spacer()
                Text("只读").font(.caption2).foregroundStyle(.secondary)
                Button(action: close) {
                    Image(systemName: "xmark").font(.caption.weight(.semibold))
                        .frame(width: 24, height: 24)
                }
                .accessibilityLabel("关闭集群监控")
            }
            .frame(height: 28)

            HStack(spacing: 6) {
                Circle().fill(cluster.enabled ? Color.green : .gray)
                    .frame(width: 7, height: 7)
                Text(cluster.enabled
                     ? "\(cluster.onlinePeers.count + 1) 台在线"
                     : "集群未启用")
                    .font(.caption.weight(.medium))
                Spacer()
                Text("局域网 · 加密传输")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            nodeView(cluster.localNode, local: true)
            if cluster.enabled {
                ForEach(cluster.peers) { node in
                    nodeView(node, local: false)
                }
                if cluster.peers.isEmpty {
                    Text("尚未收到其他已授权 Mac 的数据")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 35)
                }
            }

            VStack(alignment: .leading, spacing: 9) {
                Toggle("允许局域网共享只读监控数据",
                       isOn: Binding(get: { cluster.enabled },
                                     set: { cluster.setEnabled($0) }))
                    .disabled(!cluster.hasKey)
                    .font(.caption.weight(.medium))
                    .toggleStyle(.switch)

                HStack(spacing: 8) {
                    if !cluster.hasKey {
                        Button("生成共享密钥") { _ = cluster.createKey() }
                    } else {
                        Button("复制共享密钥") { cluster.copyKeyToPasteboard() }
                    }
                    Button("从剪贴板导入") { cluster.importKeyFromPasteboard() }
                }
                .font(.caption)

                Text(cluster.status)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("两台 Mac 使用同一共享密钥并开启监控。ChipBar 不会启动、结束或调度仿真。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(11)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 15))
        }
        .frame(width: SidePanelLayout.contentWidth(for: .cluster), alignment: .topLeading)
    }

    private func nodeView(_ node: ClusterNodeReadout, local: Bool) -> some View {
        let online = local || node.isOnline()
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: local ? "desktopcomputer" : "laptopcomputer")
                    .foregroundStyle(accent)
                Text(node.name).font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 2)
                Circle().fill(online ? Color.green : Color.gray)
                    .frame(width: 6, height: 6)
                Text(local ? "本机" : online ? "在线" : "离线")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Text(node.chip).font(.caption2).foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(spacing: 7) {
                metric("CPU", text(node.cpu, unit: "%"))
                metric("GPU", text(node.gpu, unit: "%"))
                metric("内存", node.memoryUsedGB.map {
                    String(format: "%.1f GB", $0)
                } ?? "—")
                metric("功率", text(node.chipWatts, unit: "W"))
            }
            if let temperature = node.cpuTemperatureC {
                Text(String(format: "CPU 温度 %.1f°C", temperature))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if !node.tasks.isEmpty {
                Divider()
                ForEach(node.tasks) { task in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 5) {
                            Text(task.title).font(.caption.weight(.medium))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Text(task.state).font(.caption2).foregroundStyle(.secondary)
                        }
                        if let progress = task.progress {
                            ProgressView(value: progress)
                                .tint(accent)
                                .controlSize(.mini)
                            Text(String(format: "%.0f%%", progress * 100))
                                .font(.caption2).foregroundStyle(.secondary)
                        } else {
                            Text("进度未知").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                Text("未收到外部仿真状态")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassTile(radius: 20)
        .opacity(online ? 1 : 0.6)
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 9)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 10, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func text(_ number: Double?, unit: String) -> String {
        guard let number else { return "—" }
        return String(format: "%.0f%@", number, unit)
    }
}
