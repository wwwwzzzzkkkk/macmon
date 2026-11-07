import SwiftUI
import UniformTypeIdentifiers

/// Stable identifiers: never persist an array index or a localized title.
enum DashboardTile: String, CaseIterable, Identifiable {
    case powerTrend, cpu, gpu, memory, cpuCores, fan, ane, storage, powerSupply, applications

    var id: String { rawValue }

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
        case .powerSupply: return "电源"
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

    /// Six equal layout tracks preserve v3.2.x tile proportions. Reordering
    /// changes where tiles flow but does not squash ring gauges or charts.
    var columns: Int {
        switch self {
        case .powerTrend, .cpuCores, .storage: return 6
        case .cpu, .gpu, .memory: return 2
        case .fan, .ane, .powerSupply, .applications: return 3
        }
    }
}

/// Data-only ordering; normalizing is resilient to duplicate IDs and to
/// brand-new tile kinds introduced by future versions.
struct DashboardTileArrangement: Equatable {
    var order: [DashboardTile]
    var hidden: Set<DashboardTile>

    init(savedOrder: [String]? = nil, savedHidden: [String]? = nil) {
        var found = Set<DashboardTile>()
        let decoded = (savedOrder ?? DashboardTile.allCases.map(\.rawValue))
            .compactMap(DashboardTile.init(rawValue:))
            .filter { found.insert($0).inserted }
        order = decoded + DashboardTile.allCases.filter { !found.contains($0) }
        hidden = Set((savedHidden ?? []).compactMap(DashboardTile.init(rawValue:)))
    }

    var visible: [DashboardTile] { order.filter { !hidden.contains($0) } }

    mutating func move(_ dragged: DashboardTile, before target: DashboardTile) {
        guard dragged != target,
              let source = order.firstIndex(of: dragged),
              order.contains(target) else { return }
        order.remove(at: source)
        guard let destination = order.firstIndex(of: target) else { return }
        order.insert(dragged, at: destination)
    }

    mutating func setVisible(_ tile: DashboardTile, _ visible: Bool) {
        if visible { hidden.remove(tile) } else { hidden.insert(tile) }
    }
}

final class DashboardTileLayoutModel: ObservableObject {
    static let orderKey = "chipbar.dashboard.tile-order.v1"
    static let hiddenKey = "chipbar.dashboard.hidden-tiles.v1"

    @Published private(set) var arrangement: DashboardTileArrangement {
        didSet { persist() }
    }
    @Published var editing = false
    @Published var dragging: DashboardTile?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        arrangement = DashboardTileArrangement(
            savedOrder: defaults.stringArray(forKey: Self.orderKey),
            savedHidden: defaults.stringArray(forKey: Self.hiddenKey))
    }

    var visible: [DashboardTile] { arrangement.visible }

    func move(_ dragged: DashboardTile, before target: DashboardTile) {
        guard !arrangement.hidden.contains(dragged), !arrangement.hidden.contains(target) else { return }
        arrangement.move(dragged, before: target)
    }

    func setVisible(_ tile: DashboardTile, _ visible: Bool) {
        arrangement.setVisible(tile, visible)
    }

    func reset() {
        arrangement = DashboardTileArrangement()
        editing = false
        dragging = nil
    }

    private func persist() {
        defaults.set(arrangement.order.map(\.rawValue), forKey: Self.orderKey)
        defaults.set(arrangement.hidden.map(\.rawValue).sorted(), forKey: Self.hiddenKey)
    }
}

/// Each tile measures at its allocated track width. The next tile moves into
/// the first available row space; mixed-height rows do not overlap.
private struct ChipBarTileSpan: LayoutValueKey {
    static let defaultValue = 6
}

extension View {
    func chipBarTileSpan(_ tracks: Int) -> some View {
        layoutValue(key: ChipBarTileSpan.self, value: tracks)
    }
}

struct ChipBarAdaptiveTileLayout: Layout {
    let tracks = 6
    let columnGap: CGFloat = 8
    let rowGap: CGFloat = 10

    private struct Placement {
        let origin: CGPoint
        let size: CGSize
    }

    private func measured(_ subviews: Subviews, width: CGFloat)
        -> (placements: [Placement], height: CGFloat) {
        let usableWidth = max(0, width)
        let trackWidth = max(1, (usableWidth - columnGap * CGFloat(tracks - 1)) / CGFloat(tracks))
        var placements: [Placement] = []
        var xTrack = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let span = max(1, min(tracks, subview[ChipBarTileSpan.self]))
            if xTrack + span > tracks {
                y += rowHeight + rowGap
                rowHeight = 0
                xTrack = 0
            }
            let itemWidth = CGFloat(span) * trackWidth + CGFloat(span - 1) * columnGap
            let fitted = subview.sizeThatFits(ProposedViewSize(width: itemWidth, height: nil))
            let itemHeight = max(1, fitted.height)
            placements.append(Placement(
                origin: CGPoint(x: CGFloat(xTrack) * (trackWidth + columnGap), y: y),
                size: CGSize(width: itemWidth, height: itemHeight)))
            rowHeight = max(rowHeight, itemHeight)
            xTrack += span
        }
        return (placements, placements.isEmpty ? 0 : y + rowHeight)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews,
                      cache: inout ()) -> CGSize {
        let width = proposal.width ?? 348
        return CGSize(width: width, height: measured(subviews, width: width).height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        let layout = measured(subviews, width: bounds.width)
        for (index, subview) in subviews.enumerated() {
            let item = layout.placements[index]
            subview.place(
                at: CGPoint(x: bounds.minX + item.origin.x, y: bounds.minY + item.origin.y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: item.size.width, height: item.size.height))
        }
    }
}

/// SwiftUI/NSItemProvider handles the native drag preview. Reordering on
/// dropEntered animates neighboring tiles out of the way; no timer, snapshot
/// renderer or additional sensor sampler runs during dragging.
struct ChipBarTileDropDelegate: DropDelegate {
    let target: DashboardTile
    let layout: DashboardTileLayoutModel

    func dropEntered(info: DropInfo) {
        guard let dragged = layout.dragging, dragged != target else { return }
        withAnimation(.spring(response: 0.30, dampingFraction: 0.90)) {
            layout.move(dragged, before: target)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        layout.dragging = nil
        return true
    }
}

struct ChipBarTileSettings: View {
    @ObservedObject var layout: DashboardTileLayoutModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("主页磁贴布局", systemImage: "square.grid.3x3.topleft.filled")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("恢复默认") { layout.reset() }
                    .font(.caption)
            }
            Text("在主页长按磁贴或点击“排列”，然后拖动调整位置。其他磁贴会自动让位。")
                .font(.caption2)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(DashboardTile.allCases) { tile in
                    let visible = !layout.arrangement.hidden.contains(tile)
                    Toggle(isOn: Binding(
                        get: { !layout.arrangement.hidden.contains(tile) },
                        set: { layout.setVisible(tile, $0) }
                    )) {
                        Label(tile.title, systemImage: tile.symbol)
                            .font(.caption)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .toggleStyle(.checkbox)
                    .accessibilityLabel(tile.title)
                    .accessibilityValue(visible ? "显示" : "隐藏")
                }
            }
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 13))
    }
}
