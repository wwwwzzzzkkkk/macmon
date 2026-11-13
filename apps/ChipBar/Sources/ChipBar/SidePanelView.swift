import SwiftUI

enum DashboardSidePanelKind: String, Equatable {
    case applications
    case power
    case externalDisk
    case cluster
}

/// Shared native-window sizing for each independent tile page.
enum SidePanelLayout {
    static let width: CGFloat = 314
    // 420pt window - 24pt panel margins - 24pt tile padding = 372pt canvas.
    // App ranking and disk detail retain their existing compact widths.
    static let powerWidth: CGFloat = 420
    static let padding: CGFloat = 12
    static let contentWidth: CGFloat = width - 2 * padding
    static let applicationHeight: CGFloat = 250
    // Power page is scrollable inside a stable native window; expanding a port
    // must never resize the parent menu or its glass sidecar.
    static let powerHeight: CGFloat = 640
    static let diskHeight: CGFloat = 410
    static let clusterHeight: CGFloat = 620

    static func width(for kind: DashboardSidePanelKind?) -> CGFloat {
        kind == .power ? powerWidth : kind == .cluster ? 378 : width
    }

    static func contentWidth(for kind: DashboardSidePanelKind?) -> CGFloat {
        width(for: kind) - 2 * padding
    }

    static func height(for kind: DashboardSidePanelKind) -> CGFloat {
        switch kind {
        case .applications: return applicationHeight
        case .power: return powerHeight
        case .externalDisk: return diskHeight
        case .cluster: return clusterHeight
        }
    }
}

struct SidePanelLoadingView: View {
    let kind: DashboardSidePanelKind
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(kind == .power ? "电源与功率" :
                  kind == .externalDisk ? "外置硬盘" :
                  kind == .cluster ? "计算集群" : "应用占用",
                  systemImage: kind == .power ? "bolt.horizontal.circle" :
                  kind == .externalDisk ? "externaldrive" :
                  kind == .cluster ? "point.3.connected.trianglepath.dotted" : "square.stack.3d.up")
                .font(.headline)
                .frame(height: 28)
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(0.045))
                .frame(height: kind == .applications ? 165 : 105)
                .overlay { ProgressView().controlSize(.small) }
        }
        .frame(width: SidePanelLayout.contentWidth(for: kind), alignment: .topLeading)
        .padding(SidePanelLayout.padding)
    }
}

struct DashboardSidePanelView: View {
    @ObservedObject var monitor: Monitor
    @ObservedObject var state: DashboardState
    var close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch state.sidePanel {
            case .applications:
                HStack(spacing: 8) {
                    Image(systemName: "square.stack.3d.up")
                        .foregroundStyle(Color(red: 0.22, green: 0.65, blue: 0.79))
                    Text("应用占用").font(.headline)
                    Spacer(minLength: 0)
                    Button(action: close) {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.semibold))
                            .frame(width: 24, height: 24)
                    }
                    .accessibilityLabel("关闭侧边卡片")
                }
                .frame(height: 28)
                ApplicationUsageSection(monitor: monitor, state: state,
                                        showsDisclosure: false)
            case .power:
                PowerSupplyDetailView(monitor: monitor,
                                      active: !monitor.paused && !monitor.sleeping,
                                      close: close)
            case .externalDisk:
                if let id = state.selectedExternalVolumeID {
                    ExternalDiskDetailView(volumeID: id, ssd: monitor.ssd, close: close)
                }
            case .cluster:
                ClusterMonitorPanel(monitor: monitor, close: close)
            case nil:
                EmptyView()
            }
        }
        .frame(width: SidePanelLayout.contentWidth(for: state.sidePanel), alignment: .topLeading)
        .padding(SidePanelLayout.padding)
        .buttonStyle(ChipBarPressStyle())
    }
}
