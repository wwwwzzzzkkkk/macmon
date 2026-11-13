import AppKit
import SwiftUI
import QuartzCore
import Combine

@MainActor private final class ChipBarSideWindow: NSPanel {
    var escape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { escape?() }
}

/// A second, independent native glass window. Resource and SMC samplers mount
/// only while it is visible; the main menu retains its size and cached layout.
@MainActor final class ChipBarSidePanelController {
    private let panel = ChipBarSideWindow(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                          backing: .buffered, defer: false)
    private let scrollView = NSScrollView()
    private let host = NSHostingView<AnyView>(rootView: AnyView(EmptyView()))
    private let state: DashboardState
    private let monitor: Monitor
    private let onClose: () -> Void
    private var transition = UUID()
    private var lastOpenedOnRight = true
    private var mountTask: Task<Void, Never>?
    private var clusterFitTask: Task<Void, Never>?
    private var clusterLayoutSubscription: AnyCancellable?
    private var clusterTaskSubscription: AnyCancellable?
    private var externalTaskSubscription: AnyCancellable?

    var isKeyWindow: Bool { panel.isKeyWindow }
    var isVisible: Bool { panel.isVisible }
    private var openedKind: DashboardSidePanelKind?
    private weak var parentWindow: NSWindow?
    func owns(_ other: NSWindow?) -> Bool { other === panel }

    init(monitor: Monitor, state: DashboardState, delegate: NSWindowDelegate,
         onClose: @escaping () -> Void) {
        self.state = state
        self.monitor = monitor
        self.onClose = onClose
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.verticalScrollElasticity = .automatic
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.focusRingType = .none
        scrollView.contentView.drawsBackground = false
        scrollView.contentView.focusRingType = .none
        scrollView.documentView = host
        host.setFrameSize(NSSize(width: SidePanelLayout.width,
                                 height: SidePanelLayout.applicationHeight))
        let material = PanelMaterialView(contentView: scrollView)
        panel.contentView = material
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
        panel.title = "ChipBar 侧边卡片"
        panel.delegate = delegate
        panel.escape = onClose
        let cluster = ClusterMonitorService.shared
        clusterLayoutSubscription = Publishers.CombineLatest4(
            cluster.$nearby.map(\.count),
            cluster.$peers.map { $0.map { "\($0.id):\($0.tasks.count):\($0.tasks.filter { $0.progress != nil }.count)" }.joined(separator: ";") },
            cluster.$pairingCandidate.map { $0 == nil ? 0 : 1 },
            cluster.$enabled
        )
        .map { values in "\(values.0):\(values.1):\(values.2):\(values.3)" }
        .removeDuplicates()
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in self?.scheduleClusterFit() }
        clusterTaskSubscription = cluster.$observedOpenFASTTasks
            .map { "\($0.count):\($0.filter { $0.progress != nil }.count)" }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.scheduleClusterFit() }
        externalTaskSubscription = cluster.$externalTasks
            .map { "\($0.count):\($0.filter { $0.progress != nil }.count)" }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.scheduleClusterFit() }
        // The hosted view is mounted on demand to avoid reading processes or SMC on startup.
    }

    func show(_ kind: DashboardSidePanelKind, beside parent: NSWindow) {
        guard let screen = parent.screen ?? NSScreen.main else { return }
        transition = UUID()
        mountTask?.cancel()
        let token = transition
        openedKind = kind
        parentWindow = parent
        let visible = screen.visibleFrame
        let width = SidePanelLayout.width(for: kind)
        let desiredHeight = SidePanelLayout.height(for: kind)
        let height = min(desiredHeight, max(200, visible.height - 16))
        host.setFrameSize(NSSize(width: width, height: desiredHeight))
        let spacing: CGFloat = 9
        let rightSpace = visible.maxX - parent.frame.maxX - 8
        let leftSpace = parent.frame.minX - visible.minX - 8
        let openRight = rightSpace >= width + spacing || rightSpace >= leftSpace
        lastOpenedOnRight = openRight
        let desiredX = openRight ? parent.frame.maxX + spacing : parent.frame.minX - width - spacing
        let x = min(max(visible.minX + 8, desiredX), visible.maxX - width - 8)
        let top = min(visible.maxY - 8, parent.frame.maxY)
        let y = max(visible.minY + 8, top - height)
        let target = NSRect(x: x, y: y, width: width, height: height)
        panel.appearance = parent.appearance
        host.appearance = parent.appearance
        panel.contentView?.appearance = parent.appearance

        // Present a lightweight shell first: creating the full ranking or
        // SMC SwiftUI tree synchronously delays the native window first frame.
        host.rootView = AnyView(SidePanelLoadingView(kind: kind))
        if !panel.isVisible {
            let offset: CGFloat = openRight ? -14 : 14
            panel.setFrame(target.offsetBy(dx: offset, dy: 0), display: false)
            panel.alphaValue = 0
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
        mountTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(90)) }
            catch { return }
            guard let self, self.transition == token, self.panel.isVisible,
                  self.openedKind == kind else { return }
            self.host.rootView = AnyView(DashboardSidePanelView(
                monitor: self.monitor, state: self.state, close: self.onClose
            ))
            self.mountTask = nil
            if kind == .cluster { self.scheduleClusterFit() }
        }
        let motion = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard motion else {
            panel.setFrame(target, display: true)
            panel.alphaValue = 1
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.26
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.72, 0.30, 1.0)
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 1
        } completionHandler: {
            Task { @MainActor [weak self] in self?.panel.invalidateShadow() }
        }
    }

    /// Refit only when device structure changes, not on each power sample.
    /// A short document shrinks to its intrinsic height; larger clusters
    /// scroll in a bounded panel without moving the parent menu.
    private func scheduleClusterFit() {
        guard openedKind == .cluster, panel.isVisible else { return }
        clusterFitTask?.cancel()
        let token = transition
        clusterFitTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(85)) }
            catch { return }
            guard let self, self.transition == token,
                  self.openedKind == .cluster, self.panel.isVisible,
                  let visible = self.panel.screen?.visibleFrame else { return }
            let width = SidePanelLayout.width(for: .cluster)
            // Remove the stale viewport constraint before asking SwiftUI
            // for its natural height (otherwise the empty area feeds back).
            self.host.setFrameSize(NSSize(width: width, height: 1))
            let measured = ceil(self.host.fittingSize.height)
            let intrinsic = measured.isFinite && measured > 0 ? min(2000, measured) : SidePanelLayout.clusterHeight
            let height = min(max(210, intrinsic), min(540, visible.height - 16))
            self.host.setFrameSize(NSSize(width: width,
                                          height: max(intrinsic, height)))
            let old = self.panel.frame
            let top = min(visible.maxY - 8, old.maxY)
            let y = max(visible.minY + 8, top - height)
            let frame = NSRect(x: old.minX, y: y, width: width, height: height)
            if abs(old.height - height) > 1 {
                self.panel.setFrame(frame, display: true)
            }
            self.clusterFitTask = nil
        }
    }

    func hide(animated: Bool = true) {
        transition = UUID()
        openedKind = nil
        mountTask?.cancel()
        mountTask = nil
        clusterFitTask?.cancel()
        clusterFitTask = nil
        let token = transition
        guard panel.isVisible else {
            host.rootView = AnyView(EmptyView())
            return
        }
        let complete: () -> Void = { [weak self] in
            guard let self, self.transition == token else { return }
            self.panel.orderOut(nil)
            // Cancel on-demand process and power sampling by unmounting.
            self.host.rootView = AnyView(EmptyView())
        }
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            panel.alphaValue = 0
            complete()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 0
            panel.animator().setFrame(panel.frame.offsetBy(dx: lastOpenedOnRight ? -10 : 10, dy: 0), display: true)
        } completionHandler: {
            Task { @MainActor in complete() }
        }
    }
}
