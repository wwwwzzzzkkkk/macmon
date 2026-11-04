import SwiftUI

enum DashboardSidePanelKind: String, Equatable {
    case applications
    case power
    case externalDisk
}

/// Shared native-window sizing for each independent tile page.
enum SidePanelLayout {
    static let width: CGFloat = 314
    static let padding: CGFloat = 12
    static let contentWidth: CGFloat = width - 2 * padding
    static let applicationHeight: CGFloat = 250
    static let powerHeight: CGFloat = 516
    static let diskHeight: CGFloat = 410

    static func height(for kind: DashboardSidePanelKind) -> CGFloat {
        switch kind {
        case .applications: return applicationHeight
        case .power: return powerHeight
        case .externalDisk: return diskHeight
        }
    }
}

struct SidePanelLoadingView: View {
    let kind: DashboardSidePanelKind
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(kind == .power ? "电源与功率" :
                  kind == .externalDisk ? "外置硬盘" : "应用占用",
                  systemImage: kind == .power ? "bolt.horizontal.circle" :
                  kind == .externalDisk ? "externaldrive" : "square.stack.3d.up")
                .font(.headline)
                .frame(height: 28)
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(0.045))
                .frame(height: kind == .applications ? 165 : 105)
                .overlay { ProgressView().controlSize(.small) }
        }
        .frame(width: SidePanelLayout.contentWidth, alignment: .topLeading)
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
            case nil:
                EmptyView()
            }
        }
        .frame(width: SidePanelLayout.contentWidth, alignment: .topLeading)
        .padding(SidePanelLayout.padding)
        .buttonStyle(ChipBarPressStyle())
    }
}
