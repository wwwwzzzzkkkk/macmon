import AppKit
import SwiftUI
import ChipBarCore

struct ClusterOverviewTile: View {
    @ObservedObject private var cluster = ClusterMonitorService.shared
    let selected: Bool
    let open: () -> Void
    private let accent = Color(red: 0.22, green: 0.65, blue: 0.79)

    var body: some View {
        Button(action: open) {
            HStack(spacing: 10) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(accent)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 3) {
                    Text("计算集群").font(.caption.weight(.semibold))
                    Text(cluster.enabled
                         ? "\(cluster.onlinePeers.count + 1) 台在线 · 只读监控"
                         : "点击查看附近的 Mac")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "chevron.right" : "rectangle.on.rectangle")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .frame(height: 54)
            .frame(maxWidth: .infinity)
            .glassTile(radius: 24, tint: selected ? accent.opacity(0.12) : nil,
                       interactive: true)
            .contentShape(RoundedRectangle(cornerRadius: 24))
        }
        .buttonStyle(ChipBarPressStyle())
        .accessibilityLabel("计算集群，只读监控")
    }
}

/// Follows the v3.5 glass and type hierarchy. Network controls appear only
/// where useful; no pasted secrets, simulated readings or task control.
struct ClusterMonitorPanel: View {
    @ObservedObject private var cluster = ClusterMonitorService.shared
    @ObservedObject var monitor: Monitor
    let close: () -> Void
    @State private var showNetworkHelp = false

    private let accent = Color(red: 0.22, green: 0.65, blue: 0.79)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .foregroundStyle(accent)
                Text("计算集群").font(.headline)
                Spacer(minLength: 0)
                Text("只读").font(.caption2).foregroundStyle(.secondary)
                Button { cluster.refreshDiscovery() } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 24, height: 24)
                }
                .accessibilityLabel("重新搜索附近设备")
                Button(action: close) {
                    Image(systemName: "xmark")
                        .frame(width: 24, height: 24)
                }
                .accessibilityLabel("关闭集群监控")
            }
            .frame(height: 28)

            HStack(spacing: 7) {
                Circle().fill(cluster.enabled ? Color.green : .orange)
                    .frame(width: 6, height: 6)
                Text(cluster.enabled
                     ? "\(cluster.onlinePeers.count + 1) 台在线"
                     : "等待设备配对")
                    .font(.caption.weight(.medium))
                Spacer()
                if cluster.enabled {
                    Toggle("共享", isOn: Binding(
                        get: { cluster.enabled },
                        set: { cluster.setEnabled($0) }))
                        .font(.caption2)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                }
            }
            localCard

            if !cluster.nearby.isEmpty {
                HStack {
                    Text("附近设备").font(.caption.weight(.semibold))
                    Spacer(minLength: 0)
                    Text("\(cluster.nearby.count) 台")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                ForEach(cluster.nearby) { device in
                    nearbyCard(device)
                }
            } else if cluster.onlinePeers.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .foregroundStyle(accent)
                    Text("未发现 MacBook，请确认另一台 Mac 也打开了集群页面")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
            }

            ForEach(cluster.peers.filter { peer in
                !cluster.nearby.contains(where: { $0.id == peer.id })
            }) { peer in
                remoteCard(peer)
            }

            if let pairing = cluster.pairingCandidate {
                pairingCard(pairing)
            }

            HStack(spacing: 6) {
                Text(cluster.status).font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button {
                    showNetworkHelp.toggle()
                } label: {
                    Image(systemName: "questionmark.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("雷雳桥接连接帮助")
            }
            if showNetworkHelp {
                Text("雷雳线需要建立网络：两台 Mac 打开「系统设置 → 网络 → Thunderbolt Bridge」，确认已连接并有 IP；同时允许 ChipBar 访问「隐私与安全性 → 本地网络」。")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(width: SidePanelLayout.contentWidth(for: .cluster),
               alignment: .topLeading)
        .onAppear { cluster.setPanelVisible(true) }
        .onDisappear { cluster.setPanelVisible(false) }
    }

    private var localCard: some View {
        nodeCard(cluster.localNode, local: true)
    }

    private func nearbyCard(_ device: ClusterNearbyDevice) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "laptopcomputer")
                    .foregroundStyle(accent)
                Text(device.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if device.paired {
                    Text("已配对")
                        .font(.caption2).foregroundStyle(.secondary)
                } else if cluster.pairingCandidate?.id != device.id {
                    Button("配对") { cluster.requestPairing(with: device.id) }
                        .font(.caption.weight(.medium))
                }
            }
            if device.paired,
               let reading = cluster.peers.first(where: { $0.id == device.id }) {
                metricRow(reading)
                if let temp = reading.cpuTemperatureC {
                    Text(String(format: "CPU 温度 %.1f°C", temp))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                taskList(reading)
            } else if device.paired {
                HStack {
                    ProgressView().controlSize(.mini)
                    Text("等待另一台 Mac 确认并发送数据")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassTile(radius: 20)
    }

    private func pairingCard(_ pairing: ClusterPairingCandidate) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("配对 \(pairing.name)")
                .font(.caption.weight(.semibold))
            Text(pairing.code)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .tracking(5)
                .frame(maxWidth: .infinity)
            Text("在另一台 Mac 上选择本机，核对六位数字一致，再分别确认。")
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("取消") { cluster.cancelPairing() }
                Spacer()
                Button("数字一致，确认配对") { cluster.confirmPairing() }
                    .buttonStyle(.borderedProminent)
            }
            .font(.caption)
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
    }

    private func remoteCard(_ node: ClusterNodeReadout) -> some View {
        nodeCard(node, local: false)
    }

    private func nodeCard(_ node: ClusterNodeReadout, local: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: local ? "desktopcomputer" : "laptopcomputer")
                    .foregroundStyle(accent)
                Text(node.name).font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Circle().fill(local || node.isOnline() ? Color.green : .gray)
                    .frame(width: 6, height: 6)
                Text(local ? "本机" : node.isOnline() ? "在线" : "离线")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Text(node.chip).font(.caption2).foregroundStyle(.secondary)
            metricRow(node)
            if let temp = node.cpuTemperatureC {
                Text(String(format: "CPU 温度 %.1f°C", temp))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            taskList(node)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassTile(radius: 20)
    }

    private func metricRow(_ node: ClusterNodeReadout) -> some View {
        HStack(spacing: 7) {
            metric("CPU", text(node.cpu, unit: "%"))
            metric("GPU", text(node.gpu, unit: "%"))
            metric("内存", node.memoryUsedGB.map {
                String(format: "%.1f GB", $0)
            } ?? "—")
            metric("功率", text(node.chipWatts, unit: "W"))
        }
    }

    @ViewBuilder private func taskList(_ node: ClusterNodeReadout) -> some View {
        if !node.tasks.isEmpty {
            Divider()
            ForEach(node.tasks) { task in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(task.title).font(.caption.weight(.medium))
                            .lineLimit(1)
                        Spacer()
                        Text(task.state).font(.caption2).foregroundStyle(.secondary)
                    }
                    if let value = task.progress {
                        ProgressView(value: value).tint(accent).controlSize(.mini)
                    } else {
                        Text("进度未知").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 9)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 10, weight: .semibold, design: .rounded))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func text(_ value: Double?, unit: String) -> String {
        guard let value else { return "—" }
        return String(format: "%.0f%@", value, unit)
    }
}
