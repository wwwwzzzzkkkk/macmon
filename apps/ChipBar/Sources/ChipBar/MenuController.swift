import AppKit
import SwiftUI
import Combine
import ChipBarCore

@MainActor private final class MenuPanel: NSPanel {
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

/// A transparent native panel lets the system glass sample the actual desktop,
/// rather than the opaque backing of an NSPopover. The dashboard stays unchanged.
@MainActor final class MenuController: NSObject, NSWindowDelegate {
    private let monitor: Monitor
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let panel = MenuPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private let scrollView = NSScrollView()
    private let dashboardState = DashboardState()
    private var hostingView: NSHostingView<AnyView>!
    private var dashboardMounted = false
    private var panelRequestedVisible = false
    private var panelTransition = UUID()
    private var autoDismissal: Task<Void, Never>?
    private var mouseDownTarget: Bool?
    private var mouseSequence = UUID()
    private var mouseSequenceStartedAt: TimeInterval = 0
    private var mouseReleaseCleanup: Task<Void, Never>?
    private var panelMaterial: PanelMaterialView!
    private var subscription: AnyCancellable?
    private var menuPreferences: AnyCancellable?
    private var menuRefresh: MenuRefreshDriver!
    private var disclosureSubscription: AnyCancellable?
    private var settingsNavigationSubscription: AnyCancellable?
    private var navigationViewportHeight: CGFloat?
    private var navigationTask: Task<Void, Never>?
    private var navigationToken = UUID()
    private var resetScrollForPage = false
    private struct DisclosureTransition {
        let start: (applications: Double, ssd: Double)
        let target: (applications: Double, ssd: Double)
        let began: TimeInterval
        let token: UUID
    }
    private var disclosureTransition: DisclosureTransition?
    private var measuredHeight: CGFloat = 0
    private var maximumHeight: CGFloat = 850
    private var menuTracking = false
    private var localEvents: Any?
    private var globalEvents: Any?
    private var observers: [NSObjectProtocol] = []
    private let compactMenu = CompactMenuView()
    private var mouseQATrace: [[String: Any]]?

    init(monitor: Monitor) {
        self.monitor = monitor
        super.init()
        if let button = statusItem.button {
            compactMenu.autoresizingMask = [.width, .height]
            compactMenu.setAccessibilityElement(false)
            button.addSubview(compactMenu)
            button.target = self
            button.action = #selector(togglePanel)
        }
        hostingView = NSHostingView<AnyView>(rootView: AnyView(EmptyView()))
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScrollElasticity = .none
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.focusRingType = .none
        scrollView.contentView.drawsBackground = false
        scrollView.contentView.focusRingType = .none
        scrollView.autoresizingMask = [.width, .height]
        scrollView.documentView = hostingView
        panelMaterial = PanelMaterialView(contentView: scrollView)
        panel.contentView = panelMaterial
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
        panel.title = "ChipBar"
        panel.delegate = self
        panel.onEscape = { [weak self] in self?.hidePanel(animated: false) }
        installDismissalHandlers()
        menuRefresh = MenuRefreshDriver(read: { [weak monitor] in
            await monitor?.sampleMenuSources()
            return monitor?.menuSnapshot ?? MenuSnapshot()
        }, render: { [weak self] snapshot in self?.renderMenu(snapshot) })
        configureMenuRefresh()
        menuPreferences = Publishers.MergeMany([
            monitor.$menuItems.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            monitor.$menuMetric.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            monitor.$interval.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            monitor.$paused.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            monitor.$sleeping.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            monitor.ssd.$enabled.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            monitor.ssd.$showInMenu.dropFirst().map { _ in () }.eraseToAnyPublisher()
        ]).debounce(for: .milliseconds(30), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.configureMenuRefresh() }
        refresh()
        subscription = Publishers.Merge(monitor.objectWillChange.map { _ in () },
                                        dashboardState.$ssdDetailsHeight.dropFirst().map { _ in () })
            .debounce(for: .milliseconds(30), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
        disclosureSubscription = dashboardState.$showApplications.combineLatest(dashboardState.$showSSDDetails)
            .dropFirst().receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.animateDisclosure() }
        settingsNavigationSubscription = dashboardState.$showSettings
            .dropFirst().receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.navigateSettings() }
    }

    private func navigateSettings() {
        guard dashboardMounted, panelRequestedVisible else { return }
        // Freeze the viewport only for the crossfade/slide. SwiftUI can report
        // an intermediate ZStack height while both pages are transitioning.
        navigationTask?.cancel()
        let token = UUID()
        navigationToken = token
        navigationViewportHeight = panel.frame.height
        resetScrollForPage = true
        refresh(forceLayout: true)
        navigationTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 290_000_000) } catch { return }
            guard let self, self.navigationToken == token,
                  self.dashboardMounted, self.panelRequestedVisible else { return }
            // A new measurement after the transition is essential. Retaining
            // the old settings viewport caused an occasionally truncated page.
            self.navigationViewportHeight = nil
            self.resetScrollForPage = true
            self.hostingView.layoutSubtreeIfNeeded()
            self.refresh(forceLayout: true)
            self.panel.invalidateShadow()
            self.navigationTask = nil
        }
    }

    private func animateDisclosure() {
        let target = (applications: dashboardState.showApplications ? 1.0 : 0.0,
                      ssd: dashboardState.showSSDDetails ? 1.0 : 0.0)
        let start = currentDisclosureValues()
        guard dashboardMounted, !dashboardState.showSettings,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            disclosureTransition = nil
            dashboardState.applicationsExpansion = target.applications
            dashboardState.ssdExpansion = target.ssd
            navigationViewportHeight = nil
            if dashboardMounted {
                hostingView.needsLayout = true
                refresh()
                panel.invalidateShadow()
            }
            return
        }
        navigationViewportHeight = nil
        let token = UUID()
        disclosureTransition = DisclosureTransition(start: start, target: target,
            began: ProcessInfo.processInfo.systemUptime, token: token)
        let heightDelta = CGFloat(target.applications - start.applications) * 104
            + CGFloat(target.ssd - start.ssd) * dashboardState.ssdDetailsHeight
        let targetHeight = DisclosurePanelSizing.targetHeight(
            documentHeight: measuredHeight,
            contentHeightDelta: heightDelta,
            maximumHeight: maximumHeight
        )
        withAnimation(.timingCurve(0.42, 0, 0.58, 1, duration: DashboardMotion.duration)) {
            dashboardState.applicationsExpansion = target.applications
            dashboardState.ssdExpansion = target.ssd
        }
        if let frame = panelFrame(size: NSSize(width: panel.frame.width, height: targetHeight)) {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = DashboardMotion.duration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(frame, display: true)
            } completionHandler: { [weak self] in
                Task { @MainActor in
                    guard let self, self.disclosureTransition?.token == token else { return }
                    self.disclosureTransition = nil
                    self.refresh()
                    self.panel.invalidateShadow()
                }
            }
        } else {
            disclosureTransition = nil
            refresh()
        }
    }

    private func currentDisclosureValues() -> (applications: Double, ssd: Double) {
        guard let transition = disclosureTransition else {
            return (dashboardState.applicationsExpansion, dashboardState.ssdExpansion)
        }
        let t = min(1, max(0, (ProcessInfo.processInfo.systemUptime - transition.began) / DashboardMotion.duration))
        let eased = t * t * (3 - 2 * t)
        return (
            transition.start.applications + (transition.target.applications - transition.start.applications) * eased,
            transition.start.ssd + (transition.target.ssd - transition.start.ssd) * eased
        )
    }

    private func installDismissalHandlers() {
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        let releases: NSEvent.EventTypeMask = [.leftMouseUp, .rightMouseUp, .otherMouseUp]
        globalEvents = NSEvent.addGlobalMonitorForEvents(matching: [clicks, releases]) { [weak self] event in
            let fromMenuBarOrRelease = MainActor.assumeIsolated {
                self?.recordMouseQA("globalMouseEvent", event: event)
                if [.leftMouseUp, .rightMouseUp, .otherMouseUp].contains(event.type) {
                    self?.finishUnclaimedMousePress(event)
                    return true
                }
                return self?.isMenuBarEvent(event) ?? false
            }
            // WindowServer hosts the menu bar and can deliver this same click
            // globally before forwarding it to our NSStatusBarButton.
            guard !fromMenuBarOrRelease else { return }
            MainActor.assumeIsolated { self?.dismissForFocusLoss() }
        }
        localEvents = NSEvent.addLocalMonitorForEvents(matching: [clicks, releases, .keyDown]) { [weak self] event in
            self?.recordMouseQA("localEvent", event: event)
            if [.leftMouseUp, .rightMouseUp, .otherMouseUp].contains(event.type) {
                self?.finishUnclaimedMousePress(event)
                return event
            }
            if event.type != .keyDown, self?.isStatusButtonEvent(event) == true {
                self?.autoDismissal?.cancel()
                self?.autoDismissal = nil
                self?.mouseReleaseCleanup?.cancel()
                self?.mouseSequence = UUID()
                self?.mouseSequenceStartedAt = event.timestamp
                self?.mouseDownTarget = !(self?.panelRequestedVisible ?? false)
                return event
            }
            guard let self, self.panel.isVisible else { return event }
            if event.type == .keyDown, event.keyCode == 53, !self.menuTracking {
                self.hidePanel(animated: false)
                return nil
            }
            if event.type != .keyDown, !self.menuTracking, NSApplication.shared.modalWindow == nil,
               event.window !== self.panel, !self.isStatusButtonEvent(event) {
                self.hidePanel()
            }
            return event
        }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.menuTracking = true }
        })
        observers.append(center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.menuTracking = false }
        })
        observers.append(center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.recordMouseQA("applicationResignedActive")
                self?.dismissForFocusLoss()
            }
        })
    }

    private func configureMenuRefresh() {
        menuRefresh.display(monitor.menuSnapshot)
        menuRefresh.start(every: Double(monitor.interval) / 1000, active: !monitor.paused && !monitor.sleeping)
    }

    private func renderMenu(_ snapshot: MenuSnapshot) {
        guard let button = statusItem.button else { return }
        let width = compactMenu.update(snapshot.readouts, showsLogo: snapshot.showsLogo)
        if statusItem.length != width { statusItem.length = width }
        if compactMenu.frame != button.bounds { compactMenu.frame = button.bounds }
        button.toolTip = snapshot.tooltip
        button.setAccessibilityLabel(snapshot.accessibilityLabel)
    }

    private func refresh(forceLayout: Bool = false) {
        guard dashboardMounted, forceLayout || panel.isVisible else { return }
        guard forceLayout || disclosureTransition == nil else { return }
        let switchingPage = resetScrollForPage
        let oldViewportHeight = scrollView.contentView.bounds.height
        let oldY = scrollView.contentView.bounds.origin.y
        let topOffset = hostingView.isFlipped ? oldY : max(0, hostingView.frame.height - oldViewportHeight - oldY)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        hostingView.layoutSubtreeIfNeeded()
        let height = ceil(hostingView.fittingSize.height)
        guard height.isFinite, height > 0 else { return }
        let contentHeightChanged = height != measuredHeight
        measuredHeight = height
        let size = NSSize(width: DashboardLayout.width, height: min(navigationViewportHeight ?? height, maximumHeight))
        // A short destination page still needs a full viewport-sized document,
        // otherwise NSClipView can retain an invalid origin on the next return.
        let documentHeight = max(height, size.height)
        let documentSize = NSSize(width: DashboardLayout.width, height: documentHeight)
        if hostingView.frame.size != documentSize { hostingView.setFrameSize(documentSize) }
        if let frame = panelFrame(size: size), contentHeightChanged || forceLayout {
            if frame != panel.frame { panel.setFrame(frame, display: false) }
            panelMaterial.layoutSubtreeIfNeeded()
        }
        if switchingPage || contentHeightChanged || oldViewportHeight != size.height || forceLayout {
            let maximumOffset = max(0, documentHeight - size.height)
            let offset = switchingPage ? 0 : min(maximumOffset, max(0, topOffset))
            let y = hostingView.isFlipped ? offset : maximumOffset - offset
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
        if switchingPage { resetScrollForPage = false }
    }

    private func anchor() -> (NSRect, NSScreen)? {
        guard let button = statusItem.button, let window = button.window,
              let screen = window.screen ?? NSScreen.main else { return nil }
        return (window.convertToScreen(button.convert(button.bounds, to: nil)), screen)
    }

    private func panelFrame(size: NSSize) -> NSRect? {
        guard let (rect, screen) = anchor() else { return nil }
        let visible = screen.visibleFrame
        let x = min(max(rect.maxX - size.width, visible.minX + 8), visible.maxX - size.width - 8)
        let top = (CommandLine.arguments.contains("--disclosure-only") || CommandLine.arguments.contains("--ssd-disclosure-only"))
            ? visible.maxY - 6 : min(rect.minY - 6, visible.maxY - 6)
        return NSRect(x: x, y: max(visible.minY + 8, top - size.height), width: size.width, height: size.height)
    }

    private func positionPanel() {
        if let frame = panelFrame(size: panel.frame.size), frame != panel.frame {
            panel.setFrame(frame, display: true)
        }
    }

    @objc private func togglePanel() {
        recordMouseQA("buttonAction")
        let shouldOpen = mouseDownTarget ?? !panelRequestedVisible
        mouseDownTarget = nil
        mouseReleaseCleanup?.cancel(); mouseReleaseCleanup = nil
        autoDismissal?.cancel(); autoDismissal = nil
        if !shouldOpen { hidePanel(); return }
        guard let (rect, screen) = anchor() else { return }
        maximumHeight = max(250, min(rect.minY - 6, screen.visibleFrame.maxY - 6) - screen.visibleFrame.minY - 8)
        if !dashboardMounted {
            dashboardState.applicationsExpansion = dashboardState.showApplications ? 1 : 0
            dashboardState.ssdExpansion = dashboardState.showSSDDetails ? 1 : 0
            hostingView.rootView = AnyView(Dashboard(monitor: monitor, state: dashboardState))
            if CommandLine.arguments.contains("--light") {
                hostingView.rootView = AnyView(hostingView.rootView.environment(\.colorScheme, .light))
            } else if CommandLine.arguments.contains("--dark") {
                hostingView.rootView = AnyView(hostingView.rootView.environment(\.colorScheme, .dark))
            }
            dashboardMounted = true
        }
        monitor.setDashboardVisible(true)
        refresh(forceLayout: true)
        positionPanel()
        if !panel.isVisible { panel.alphaValue = 0 }
        panelRequestedVisible = true
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(nil)
        panel.displayIfNeeded()
        animatePanel(visible: true)
    }

    private func hidePanel(animated: Bool = true) {
        autoDismissal?.cancel(); autoDismissal = nil
        mouseDownTarget = nil
        mouseReleaseCleanup?.cancel(); mouseReleaseCleanup = nil
        guard panelRequestedVisible else { return }
        panelRequestedVisible = false
        monitor.setDashboardVisible(false)
        animatePanel(visible: false, animated: animated)
    }

    private func animatePanel(visible: Bool, animated: Bool = true) {
        let token = UUID()
        panelTransition = token
        statusItem.button?.highlight(false)
        compactMenu.needsDisplay = true
        let complete: () -> Void = { [weak self] in
            guard let self, self.panelTransition == token else { return }
            if visible {
                self.statusItem.button?.highlight(false)
                self.panel.invalidateShadow()
            } else {
                self.panel.orderOut(nil)
                self.removeDashboard()
            }
        }
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            panel.alphaValue = visible ? 1 : 0
            complete()
            return
        }
        // AppKit animates opacity on the existing window; reversing a transition
        // keeps its current opacity. Old completions cannot hide a reopened panel.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = visible ? DashboardMotion.popoverEnter : DashboardMotion.popoverExit
            context.timingFunction = DashboardMotion.popoverCurve
            panel.animator().alphaValue = visible ? 1 : 0
        } completionHandler: {
            Task { @MainActor in complete() }
        }
    }

    private func removeDashboard() {
        guard dashboardMounted else { return }
        disclosureTransition = nil
        // Hidden NSPanel content still observes Monitor. Remove the dashboard so
        // it cannot keep updating offscreen; settings live separately.
        hostingView.rootView = AnyView(EmptyView())
        dashboardMounted = false
        measuredHeight = 0
        navigationTask?.cancel()
        navigationTask = nil
        navigationToken = UUID()
        navigationViewportHeight = nil
        resetScrollForPage = false
    }

    func windowDidResignKey(_ notification: Notification) {
        recordMouseQA("panelResignedKey")
        dismissForFocusLoss()
    }

    private func dismissForFocusLoss() {
        guard panelRequestedVisible, mouseDownTarget == nil else { return }
        autoDismissal?.cancel()
        let transition = panelTransition
        // Let WindowServer finish forwarding a status-button press. Native mouse
        // down freezes its toggle target and cancels this speculative dismissal.
        autoDismissal = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 150_000_000) } catch { return }
            guard let self, self.panelTransition == transition, !self.menuTracking, self.mouseDownTarget == nil,
                  NSApplication.shared.modalWindow == nil else { return }
            self.hidePanel()
        }
    }

    private func isMenuBarEvent(_ event: NSEvent) -> Bool {
        // The hosted menu-bar window is separate from the button's virtual
        // NSWindow. Its layer is stable even when live cursor/frame values lag.
        if event.windowNumber > 0, event.windowNumber <= Int(UInt32.max),
           let windows = CGWindowListCopyWindowInfo(.optionIncludingWindow, CGWindowID(event.windowNumber)) as? [[String: Any]],
           windows.contains(where: { ($0[kCGWindowLayer as String] as? Int) == NSWindow.Level.mainMenu.rawValue }) {
            return true
        }
        return isStatusButtonEvent(event)
    }

    private func isStatusButtonEvent(_ event: NSEvent) -> Bool {
        guard let window = statusItem.button?.window else { return false }
        return event.window === window || event.windowNumber > 0 && event.windowNumber == window.windowNumber
    }

    private func finishUnclaimedMousePress(_ event: NSEvent) {
        guard mouseDownTarget != nil, event.timestamp >= mouseSequenceStartedAt else { return }
        mouseReleaseCleanup?.cancel()
        let sequence = mouseSequence
        mouseReleaseCleanup = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 150_000_000) } catch { return }
            guard let self, self.mouseSequence == sequence, self.mouseDownTarget != nil else { return }
            self.mouseDownTarget = nil
            if !self.panel.isKeyWindow { self.dismissForFocusLoss() }
        }
    }

    private var pointerOverStatusItem: Bool {
        anchor()?.0.contains(NSEvent.mouseLocation) ?? false
    }

    private func recordMouseQA(_ name: String, event: NSEvent? = nil) {
        guard mouseQATrace != nil else { return }
        let event = event ?? NSApplication.shared.currentEvent
        mouseQATrace?.append([
            "event": name, "time": ProcessInfo.processInfo.systemUptime,
            "eventType": event?.type.rawValue ?? 0, "eventWindow": event?.windowNumber ?? 0,
            "statusWindow": statusItem.button?.window?.windowNumber ?? 0,
            "pressedMouseButtons": NSEvent.pressedMouseButtons,
            "requestedVisible": panelRequestedVisible, "panelVisible": panel.isVisible,
            "pointerOverStatusItem": anchor()?.0.contains(NSEvent.mouseLocation) ?? false
        ])
    }

    /// Send mouse down/up through WindowServer rather than invoking a button action.
    func verifyMouseClicks(directory: String) async {
        guard CGPreflightPostEventAccess() else { failVerification("Mouse QA needs existing event-posting permission.") }
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier != "com.apple.loginwindow" else {
            failVerification("Mouse QA requires an unlocked desktop.")
        }
        hidePanel(animated: false)
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard !panelRequestedVisible, !panel.isVisible else { failVerification("Mouse QA could not reset the panel.") }
        mouseQATrace = []
        let originalPosition = CGEvent(source: nil)?.location
        defer { if let originalPosition { CGWarpMouseCursorPosition(originalPosition) } }
        var states: [Bool] = []
        var visibility: [Bool] = []
        let args = CommandLine.arguments
        let pressIndex = args.firstIndex(of: "--mouse-press-ms")
        let pressMilliseconds = pressIndex.flatMap { args.count > $0 + 1 ? Int(args[$0 + 1]) : nil } ?? 100
        let driverIndex = args.firstIndex(of: "--mouse-driver")
        let driverPath = driverIndex.flatMap { args.count > $0 + 1 ? args[$0 + 1] : nil }
        let busyUI = args.contains("--busy-ui")
        let countIndex = args.firstIndex(of: "--mouse-click-count")
        let clickCount = countIndex.flatMap { args.count > $0 + 1 ? Int(args[$0 + 1]) : nil } ?? 4
        guard (0...1000).contains(pressMilliseconds) else { failVerification("Mouse press must be 0–1000 milliseconds.") }
        guard (1...100).contains(clickCount) else { failVerification("Mouse click count must be 1–100.") }
        for _ in 0..<clickCount {
            guard let (rect, _) = anchor(), let top = NSScreen.screens.first?.frame.maxY else {
                failVerification("Cannot locate status item for mouse QA.")
            }
            var position = CGPoint(x: rect.midX, y: top - rect.midY)
            let application = AXUIElementCreateApplication(getpid())
            var extras: CFTypeRef?
            if AXUIElementCopyAttributeValue(application, "AXExtrasMenuBar" as CFString, &extras) == .success,
               let extras, CFGetTypeID(extras) == AXUIElementGetTypeID() {
                var children: CFTypeRef?
                AXUIElementCopyAttributeValue(unsafeBitCast(extras, to: AXUIElement.self), "AXChildren" as CFString, &children)
                if let item = (children as? [AXUIElement])?.first {
                    var origin: CFTypeRef?
                    var size: CFTypeRef?
                    AXUIElementCopyAttributeValue(item, "AXPosition" as CFString, &origin)
                    AXUIElementCopyAttributeValue(item, "AXSize" as CFString, &size)
                    if let origin, let size {
                        var point = CGPoint.zero
                        var dimensions = CGSize.zero
                        AXValueGetValue(unsafeBitCast(origin, to: AXValue.self), .cgPoint, &point)
                        AXValueGetValue(unsafeBitCast(size, to: AXValue.self), .cgSize, &dimensions)
                        position = CGPoint(x: point.x + dimensions.width / 2, y: point.y + dimensions.height / 2)
                    }
                }
            }
            if let driverPath {
                let driver = Process()
                driver.executableURL = URL(fileURLWithPath: driverPath)
                driver.arguments = [String(Double(position.x)), String(Double(position.y)), String(pressMilliseconds)]
                do { try driver.run() } catch { failVerification(error.localizedDescription) }
                // Only QA stalls the UI to exercise delivery after mouse release.
                if busyUI { usleep(useconds_t(700_000 + pressMilliseconds * 1000)) }
                while driver.isRunning { try? await Task.sleep(nanoseconds: 20_000_000) }
                guard driver.terminationStatus == 0 else { failVerification("External mouse driver failed.") }
                try? await Task.sleep(nanoseconds: 450_000_000)
            } else {
                CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: position, mouseButton: .left)?.post(tap: .cghidEventTap)
                try? await Task.sleep(nanoseconds: 50_000_000)
                let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: position, mouseButton: .left)
                down?.setIntegerValueField(.mouseEventClickState, value: 1)
                down?.post(tap: .cghidEventTap)
                if pressMilliseconds > 0 { try? await Task.sleep(nanoseconds: UInt64(pressMilliseconds) * 1_000_000) }
                let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: position, mouseButton: .left)
                up?.setIntegerValueField(.mouseEventClickState, value: 1)
                up?.post(tap: .cghidEventTap)
                try? await Task.sleep(nanoseconds: 450_000_000)
            }
            states.append(panelRequestedVisible)
            visibility.append(panel.isVisible)
            recordMouseQA("clickCompleted")
        }
        let result: [String: Any] = ["pressMilliseconds": pressMilliseconds, "externalDriver": driverPath != nil, "busyUI": busyUI,
            "statesAfterClicks": states, "visibleAfterClicks": visibility, "trace": mouseQATrace ?? []]
        do {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: directory + "/mouse-clicks.json"))
        } catch { failVerification(error.localizedDescription) }
        if let originalPosition { CGWarpMouseCursorPosition(originalPosition) }
        let expected = (0..<clickCount).map { $0.isMultiple(of: 2) }
        guard states == expected, visibility == states else {
            failVerification("Actual mouse clicks did not alternate open/closed: \(states)")
        }
        monitor.stop(forQuit: true)
        NSApplication.shared.terminate(nil)
    }

    /// Exercise the actual status item and glass panel, using live metrics.
    func verifyUI(directory: String) {
        if CommandLine.arguments.contains("--light") { panel.appearance = NSAppearance(named: .aqua) }
        if CommandLine.arguments.contains("--dark") { panel.appearance = NSAppearance(named: .darkAqua) }
        guard monitor.connected else { failVerification("UI verification needs live macmon data.") }
        if (CommandLine.arguments.contains("--disclosure-only") || CommandLine.arguments.contains("--ssd-disclosure-only") || CommandLine.arguments.contains("--scroll-only")) { menuTracking = true }
        let previousApplication = NSWorkspace.shared.frontmostApplication?.processIdentifier
        statusItem.button?.performClick(nil)
        if CommandLine.arguments.contains("--scroll-only") {
            maximumHeight = min(maximumHeight, 400)
            refresh(forceLayout: true)
            Task { @MainActor in await self.verifySettingsScrolling(directory: directory) }
            return
        }
        if (CommandLine.arguments.contains("--disclosure-only") || CommandLine.arguments.contains("--ssd-disclosure-only")) {
            // A fixed preview viewport also works when the menu-bar host is hidden.
            maximumHeight = min(850, (panel.screen ?? NSScreen.main)?.visibleFrame.height ?? 850) - 16
            refresh(forceLayout: true)
            Task { @MainActor in await self.verifyDisclosures(directory: directory, previousApplication: previousApplication) }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in
            do {
                try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
                try capture(view: statusItem.button!, path: directory + "/menu-bar.png")
                try capture(view: panelMaterial, path: directory + "/popover.png")
                captureScreenWindow(path: directory + "/screen-popover.png")
                let collapsedHeight = panel.frame.height
                dashboardState.showSettings = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in
                    do {
                        try capture(view: panelMaterial, path: directory + "/popover-settings.png")
                        captureScreenWindow(path: directory + "/screen-settings.png")
                        let result: [String: Any] = [
                            "title": statusItem.button!.title, "menuText": monitor.menuText,
                            "statusWidth": statusItem.button!.bounds.width,
                            "collapsedHeight": collapsedHeight, "settingsHeight": panel.frame.height,
                            "measuredSettingsHeight": measuredHeight, "viewHeight": scrollView.bounds.height,
                            "windowHeight": panel.frame.height, "panelVisible": panel.isVisible,
                            "maximumHeight": maximumHeight, "material": panelMaterial.materialName,
                            "materialClass": panelMaterial.materialClassName,
                            "reduceTransparency": NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
                            "hostingOpaque": hostingView.isOpaque, "windowOpaque": panel.isOpaque,
                            "appearance": String(describing: panelMaterial.effectiveAppearance.name),
                            "windowId": panel.windowNumber, "frame": NSStringFromRect(panel.frame),
                            "screenFrame": NSStringFromRect(panel.screen?.frame ?? .zero),
                            "onActiveSpace": panel.isOnActiveSpace,
                            "sharing": panel.sharingType.rawValue,
                            "cgWindow": ((CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]]) ?? []).filter { ($0[kCGWindowNumber as String] as? Int) == panel.windowNumber }
                        ]
                        let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
                        try data.write(to: URL(fileURLWithPath: directory + "/layout.json"))
                        guard monitor.menuText.contains("W"), panel.isVisible,
                              dashboardState.showSettings,
                              abs(panel.frame.height - collapsedHeight) < 1,
                              abs(scrollView.bounds.height - panel.frame.height) < 1 else {
                            failVerification("Menu title or panel sizing verification failed.")
                        }
                        Task { @MainActor in await self.verifyPanelTransitions(directory: directory) }
                    } catch { failVerification(error.localizedDescription) }
                }
            } catch { failVerification(error.localizedDescription) }
        }
    }

    /// Regression: a periodic refresh must not scroll an open settings panel back down.
    private func verifySettingsScrolling(directory: String) async {
        do {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            dashboardState.showSettings = true
            try await Task.sleep(nanoseconds: 600_000_000)
            refresh()
            let maxOffset = max(0, hostingView.frame.height - scrollView.contentView.bounds.height)
            guard maxOffset > 0, dashboardState.showSettings else { failVerification("Settings did not finish opening in a scrollable panel.") }
            let expectedTop: CGFloat = hostingView.isFlipped ? 0 : maxOffset
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: expectedTop))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            let before = scrollView.contentView.bounds.origin.y
            for _ in 0..<4 {
                refresh()
                try await Task.sleep(nanoseconds: 80_000_000)
            }
            let after = scrollView.contentView.bounds.origin.y
            guard abs(after - before) < 1 else { failVerification("Refreshing settings moved the user's scroll position.") }
            try capture(view: statusItem.button!, path: directory + "/compact-menu.png")
            try capture(view: panelMaterial, path: directory + "/settings-scrolled-top.png")
            let result: [String: Any] = ["scrollBefore": before, "scrollAfter": after, "maximumOffset": maxOffset,
                                         "statusWidth": statusItem.length, "menuText": monitor.menuText,
                                         "settingsOpen": dashboardState.showSettings, "refreshes": 4]
            try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
                .write(to: URL(fileURLWithPath: directory + "/scroll-regression.json"))
            monitor.stop(forQuit: true)
            NSApplication.shared.terminate(nil)
        } catch { failVerification(error.localizedDescription) }
    }

    /// Short visual check for content disclosure, without running menu stress checks.
    private func verifyDisclosures(directory: String, previousApplication: pid_t?) async {
        let ssdOnly = CommandLine.arguments.contains("--ssd-disclosure-only")
        func toggleDetail() {
            if ssdOnly { dashboardState.showSSDDetails.toggle() } else { dashboardState.toggleApplications() }
        }
        do {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            try await Task.sleep(nanoseconds: 2_600_000_000)
            guard panel.isVisible, dashboardMounted else { failVerification("Disclosure panel was dismissed before capture.") }
            var frames: [[String: Any]] = []
            func record(_ name: String) throws {
                frames.append(["state": name, "height": panel.frame.height, "top": panel.frame.maxY,
                               "alpha": panel.alphaValue, "mounted": dashboardMounted,
                               "previousApplication": previousApplication ?? -1,
                               "frontmostApplication": NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1,
                               "chipbarActive": NSApplication.shared.isActive,
                               "hostingY": hostingView.frame.origin.y, "hostingHeight": hostingView.frame.height,
                               "clipY": scrollView.contentView.bounds.origin.y, "flipped": hostingView.isFlipped,
                               "applicationsExpansion": dashboardState.applicationsExpansion,
                               "settingsScreen": dashboardState.showSettings,
                               "ssdExpansion": dashboardState.ssdExpansion,
                               "ssdDetailsHeight": dashboardState.ssdDetailsHeight,
                               "scrollBorder": scrollView.borderType.rawValue,
                               "cornerClipped": panelMaterial.layer?.masksToBounds ?? false])
                try capture(view: panelMaterial, path: directory + "/\(name).png")
            }
            try record("collapsed")
            toggleDetail()
            try await Task.sleep(nanoseconds: 90_000_000)
            try record("expanding")
            try await Task.sleep(nanoseconds: 300_000_000)
            try record("expanded")
            toggleDetail()
            try await Task.sleep(nanoseconds: 90_000_000)
            try record("collapsing")
            try await Task.sleep(nanoseconds: 260_000_000)
            try record("collapsed-again")
            if !ssdOnly {
                let initialHeight = panel.frame.height
                dashboardState.toggleSettings()
                try await Task.sleep(nanoseconds: 350_000_000)
                guard dashboardState.showSettings, panel.alphaValue == 1,
                      abs(panel.frame.height - initialHeight) < 1 else {
                    failVerification("Settings navigation resized or faded the glass panel.")
                }
                try record("settings")
                dashboardState.toggleSettings()
                try await Task.sleep(nanoseconds: 350_000_000)
                guard !dashboardState.showSettings, panel.alphaValue == 1,
                      abs(panel.frame.height - initialHeight) < 1 else {
                    failVerification("Returning from settings resized or faded the glass panel.")
                }
                try record("settings-closed")
            }
            captureScreenWindow(path: directory + "/rounded-window-shadow.png", includeShadow: true)
            let data = try JSONSerialization.data(withJSONObject: frames, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: directory + "/disclosures.json"))
            monitor.stop(forQuit: true)
            NSApplication.shared.terminate(nil)
        } catch { failVerification(error.localizedDescription) }
    }

    private func verifyPanelTransitions(directory: String) async {
        statusItem.button?.performClick(nil)
        guard !panelRequestedVisible else { failVerification("Second status click did not request dismissal.") }
        try? await Task.sleep(nanoseconds: 60_000_000)
        let closingAlpha = panel.alphaValue
        try? await Task.sleep(nanoseconds: 250_000_000)
        guard !panel.isVisible, !dashboardMounted, panel.alphaValue == 0 else {
            failVerification("Animated panel dismissal failed.")
        }
        statusItem.button?.performClick(nil)
        try? await Task.sleep(nanoseconds: 60_000_000)
        let openingAlpha = panel.alphaValue
        try? await Task.sleep(nanoseconds: 250_000_000)
        guard panel.isVisible, dashboardMounted, dashboardState.showSettings, panel.alphaValue == 1 else {
            failVerification("Panel reopening or settings preservation failed.")
        }
        // Close, then reopen while fade-out is still in flight.
        togglePanel()
        try? await Task.sleep(nanoseconds: 30_000_000)
        togglePanel()
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard panelRequestedVisible, panel.isVisible, dashboardMounted, panel.alphaValue == 1 else {
            failVerification("Interrupted close hid a reopened panel.")
        }
        // Rapid reversals must end in the requested state, with one window.
        for _ in 0..<10 {
            togglePanel()
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard panelRequestedVisible, panel.isVisible, panel.alphaValue == 1 else {
            failVerification("Rapid status toggles left the wrong panel state.")
        }
        panel.cancelOperation(nil)
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard !panel.isVisible, !dashboardMounted else { failVerification("Escape dismissal failed.") }
        togglePanel()
        try? await Task.sleep(nanoseconds: 300_000_000)
        if let event = NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1) {
            NSApplication.shared.postEvent(event, atStart: true)
        }
        try? await Task.sleep(nanoseconds: 350_000_000)
        guard !panel.isVisible, !dashboardMounted else { failVerification("Outside click dismissal failed.") }
        togglePanel()
        hidePanel(animated: false)
        guard !panel.isVisible, !dashboardMounted else { failVerification("Immediate dismissal failed.") }
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard !panel.isVisible, !dashboardMounted else { failVerification("Old animation undid immediate dismissal.") }
        let result: [String: Any] = [
            "openingAlphaAt60ms": openingAlpha,
            "closingAlphaAt60ms": closingAlpha,
            "reduceMotion": NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            "toggleAndDismissalChecksPassed": true,
            "dashboardUnmountedAfterDismissal": !dashboardMounted
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: directory + "/transitions.json"))
        } catch { failVerification(error.localizedDescription) }
        monitor.stop(forQuit: true)
        NSApplication.shared.terminate(nil)
    }

    private func failVerification(_ message: String) -> Never {
        monitor.stop(forQuit: true)
        fputs(message + "\n", stderr)
        exit(1)
    }

    // WindowServer capture includes blur/refraction omitted by bitmap caching.
    private func captureScreenWindow(path: String, includeShadow: Bool = false) {
        guard CGPreflightScreenCaptureAccess() else { return }
        panel.displayIfNeeded()
        CATransaction.flush()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x"] + (includeShadow ? [] : ["-o"]) + ["-l", String(panel.windowNumber), path]
        do { try process.run(); process.waitUntilExit() } catch { return }
    }

    private func capture(view: NSView, path: String) throws {
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw NSError(domain: "ChipBar.UI", code: 2)
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "ChipBar.UI", code: 3)
        }
        try png.write(to: URL(fileURLWithPath: path))
    }
}
