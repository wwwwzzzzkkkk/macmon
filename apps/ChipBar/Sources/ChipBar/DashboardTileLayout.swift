import SwiftUI

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
        move(dragged, relativeTo: target, after: false)
    }

    mutating func move(_ dragged: DashboardTile, relativeTo target: DashboardTile,
                       after: Bool) {
        guard dragged != target,
              let source = order.firstIndex(of: dragged),
              order.contains(target) else { return }
        var candidate = order
        candidate.remove(at: source)
        guard let targetIndex = candidate.firstIndex(of: target) else { return }
        candidate.insert(dragged, at: targetIndex + (after ? 1 : 0))
        if candidate != order { order = candidate }
    }

    mutating func moveToEnd(_ dragged: DashboardTile) {
        guard let index = order.firstIndex(of: dragged) else { return }
        guard index != order.count - 1 else { return }
        order.remove(at: index)
        order.append(dragged)
    }

    mutating func setVisible(_ tile: DashboardTile, _ visible: Bool) {
        if visible { hidden.remove(tile) } else { hidden.insert(tile) }
    }
}

/// Pointer updates are isolated from the main dashboard's published state.
@MainActor final class ChipBarTilePointerMotion: ObservableObject {
    @Published private(set) var location: CGPoint?
    @Published private(set) var draggedTile: DashboardTile?
    @Published private(set) var size: CGSize = .zero

    func begin(tile: DashboardTile, location: CGPoint, size: CGSize) {
        draggedTile = tile
        self.size = size
        self.location = location
    }

    func follow(_ point: CGPoint) {
        guard location != point else { return }
        location = point
    }

    func clear() {
        location = nil
        draggedTile = nil
    }
}

final class DashboardTileLayoutModel: ObservableObject {
    static let shared = DashboardTileLayoutModel()
    static let orderKey = "chipbar.dashboard.tile-order.v1"
    static let hiddenKey = "chipbar.dashboard.hidden-tiles.v1"

    @Published private(set) var arrangement: DashboardTileArrangement {
        didSet {
            // Save once per release, not on every pointer/hover event.
            if dragging == nil { persist() }
        }
    }
    @Published var editing = false {
        didSet { if oldValue != editing { layoutRevision &+= 1 } }
    }
    // Only structural boundaries trigger AppKit height measurement; animated
    // reorders between those boundaries stay entirely inside SwiftUI Layout.
    @Published private(set) var layoutRevision = 0
    @Published var dragging: DashboardTile?
    @Published var highlighted: DashboardTile?
    @Published var settling: DashboardTile?
    let pointer = ChipBarTilePointerMotion()
    // Frame preferences are layout measurements, not published model changes.
    // Only reorder boundaries need to refresh the main Dashboard tree.
    var tileFrames: [DashboardTile: CGRect] = [:]
    private var landingID = UUID()
    private var lastReflowPoint: CGPoint?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        arrangement = DashboardTileArrangement(
            savedOrder: defaults.stringArray(forKey: Self.orderKey),
            savedHidden: defaults.stringArray(forKey: Self.hiddenKey))
    }

    var visible: [DashboardTile] { arrangement.visible }

    func select(_ tile: DashboardTile, reduceMotion: Bool) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.7)) {
            editing = true
            highlighted = tile
            settling = nil
        }
    }

    func cancelSelection(reduceMotion: Bool) {
        guard dragging == nil else { return }
        withAnimation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.85)) {
            highlighted = nil
        }
    }

    func beginDrag(_ tile: DashboardTile, at point: CGPoint, reduceMotion: Bool) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.78)) {
            editing = true
            highlighted = tile
            dragging = tile
            settling = nil
        }
        lastReflowPoint = point
        pointer.begin(tile: tile, location: point,
                      size: tileFrames[tile]?.size ?? CGSize(width: 112, height: 85))
    }

    /// Pointer tracking does not emit Dashboard objectWillChange. Reflow only
    /// when crossing another tile's midpoint; no system NSItemProvider session
    /// or macOS drag preview has to activate in the borderless menu panel.
    func updateDrag(_ tile: DashboardTile, at point: CGPoint, reduceMotion: Bool) {
        guard dragging == tile else { return }
        pointer.follow(point)

        let candidates = tileFrames.filter { $0.key != tile && !arrangement.hidden.contains($0.key) }
        guard !candidates.isEmpty else { return }
        // Prevent oscillation when the hovered target itself animates away.
        if let lastReflowPoint,
           hypot(point.x - lastReflowPoint.x, point.y - lastReflowPoint.y) < 12 {
            return
        }

        if let last = candidates.max(by: { $0.value.maxY < $1.value.maxY }),
           point.y > last.value.maxY + 12 {
            if arrangement.order.last != tile {
                withAnimation(reduceMotion ? nil :
                              .spring(response: 0.31, dampingFraction: 0.88)) {
                    moveToEnd(tile)
                }
                lastReflowPoint = point
            }
            return
        }

        guard let closest = candidates.min(by: { first, second in
            Self.distanceSquared(point, to: first.value) <
                Self.distanceSquared(point, to: second.value)
        }) else { return }
        let rect = closest.value
        let after: Bool = rect.width >= 240
            ? point.y > rect.midY
            : point.x > rect.midX
        let current = arrangement.order.firstIndex(of: tile)
        let other = arrangement.order.firstIndex(of: closest.key)
        guard let current, let other else { return }
        let destination = other + (after ? (current > other ? 1 : 0) :
                                  (current < other ? -1 : 0))
        guard destination != current else { return }
        withAnimation(reduceMotion ? nil :
                      .spring(response: 0.31, dampingFraction: 0.88)) {
            arrangement.move(tile, relativeTo: closest.key, after: after)
        }
        lastReflowPoint = point
    }

    private static func distanceSquared(_ point: CGPoint, to rect: CGRect) -> CGFloat {
        let x = max(rect.minX, min(rect.maxX, point.x))
        let y = max(rect.minY, min(rect.maxY, point.y))
        return pow(x - point.x, 2) + pow(y - point.y, 2)
    }

    func finishDrop(reduceMotion: Bool) {
        guard let tile = dragging else { return }
        let token = UUID()
        landingID = token
        pointer.clear()
        lastReflowPoint = nil
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.07)) {
            dragging = nil
            highlighted = nil
            settling = tile
        }
        persist()
        layoutRevision &+= 1
        // Two joined phases: compress on contact, then spring to the exact
        // resting frame. A token prevents a quick second drag from being
        // cleared by the preceding landing animation.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(75))
            guard let self, self.landingID == token else { return }
            withAnimation(reduceMotion ? nil :
                          .spring(response: 0.34, dampingFraction: 0.67)) {
                self.settling = nil
            }
        }
    }

    func finishEditing(reduceMotion: Bool) {
        landingID = UUID()
        pointer.clear()
        lastReflowPoint = nil
        withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.84)) {
            editing = false
            highlighted = nil
            dragging = nil
            settling = nil
        }
    }

    func moveToEnd(_ dragged: DashboardTile) {
        guard !arrangement.hidden.contains(dragged) else { return }
        arrangement.moveToEnd(dragged)
    }

    func move(_ dragged: DashboardTile, before target: DashboardTile) {
        guard !arrangement.hidden.contains(dragged), !arrangement.hidden.contains(target) else { return }
        arrangement.move(dragged, before: target)
    }

    func setVisible(_ tile: DashboardTile, _ visible: Bool) {
        guard arrangement.hidden.contains(tile) == visible else { return }
        arrangement.setVisible(tile, visible)
        layoutRevision &+= 1
    }

    func reset() {
        arrangement = DashboardTileArrangement()
        editing = false
        dragging = nil
        highlighted = nil
        settling = nil
        landingID = UUID()
        pointer.clear()
        tileFrames = [:]
        lastReflowPoint = nil
        layoutRevision &+= 1
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

/// Each tile reports its stable slot rectangle in the mosaic coordinate
/// space. These preferences are read without publishing per-frame state.
struct ChipBarTileFramePreference: PreferenceKey {
    static var defaultValue: [DashboardTile: CGRect] = [:]
    static func reduce(value: inout [DashboardTile: CGRect],
                       nextValue: () -> [DashboardTile: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

struct ChipBarFloatingDragTile: View {
    @ObservedObject var motion: ChipBarTilePointerMotion

    var body: some View {
        GeometryReader { _ in
            if let tile = motion.draggedTile, let location = motion.location {
                VStack(spacing: 8) {
                    Image(systemName: tile.symbol)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(tile.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(width: motion.size.width, height: motion.size.height)
                .background(.regularMaterial,
                            in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.80), lineWidth: 1.8)
                }
                .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
                .scaleEffect(1.035)
                .position(x: location.x, y: location.y - 5)
                // Never spring the cursor; only neighboring tile layout is
                // animated. The selected tile stays directly under the mouse.
                .transaction { $0.animation = nil }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
