import AppKit
import SwiftUI
import QuartzCore

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

    var isKeyWindow: Bool { panel.isKeyWindow }
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
        host.setFrameSize(NSSize(width: 334, height: 383))
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
        // The hosted view is mounted on demand to avoid reading processes or SMC on startup.
    }

    func show(beside parent: NSWindow) {
        guard state.sidePanel != nil,
              let screen = parent.screen ?? NSScreen.main else { return }
        transition = UUID()
        let visible = screen.visibleFrame
        let width: CGFloat = 334
        let desiredHeight: CGFloat = state.sidePanel == .power ? 471 : 383
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

        // The view observes DashboardState, so switching tabs preserves its
        // SwiftUI identity and the existing rank transition.
        if !panel.isVisible {
            host.rootView = AnyView(DashboardSidePanelView(
                monitor: monitor, state: state, close: onClose
            ))
            let offset: CGFloat = openRight ? -14 : 14
            panel.setFrame(target.offsetBy(dx: offset, dy: 0), display: false)
            panel.alphaValue = 0
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.makeKeyAndOrderFront(nil)
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

    func hide(animated: Bool = true) {
        transition = UUID()
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
