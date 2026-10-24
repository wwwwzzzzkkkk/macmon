# ChipBar 2.0 · Motion-first Preview

**Branch:** `chipbar-2.0-motion-first-preview`  
**Development bundle version:** `2.0.0`  
**Release policy:** development CI artifact only; do **not** merge/publish until user tests UI transitions and authorizes a stable Release.

## Product direction

Keep original two-line status-bar design, signature watts typography and restrained native Liquid Glass. Make the 370-point popup a focused, layered dashboard. Design for comfortable trackpad scrolling and expressive but unobtrusive interactions.

## Implemented in first 2.0 development build

1. **Hierarchy** — power, animated utilization rings, app ranking, and power trend remain immediately visible. A unified System Details disclosure reveals built-in storage, fan telemetry, and external SSD information, while memory/temperature summaries remain visible.
2. **Shared visual components** — `ChipBarMotion`, `ChipBarPressStyle`, `ChipBarSectionToggle`, `PowerMetricCard`, `AnimatedMetricValue`, and `CapacityProgressTrack` replace duplicated, uncoordinated controls. Controls animate press feedback and state transitions, respecting Reduce Motion.
3. **Sampling/view decoupling, phase 1** — `PanelLayoutCoordinator` coalesces expensive `NSHostingView.fittingSize` checks instead of measuring on every sensor update. Bounds notifications defer automatic resizing during scrolling momentum. The internal storage model reuses cached results when its view is remounted.
4. **Motion stability** — preserve the existing animated settings navigation and AppKit window-height easing; wait for the new section spring to settle before measuring, prevent jumping to the top for system disclosure, and preserve scroll offsets.
5. **Automated checks** — unit coverage for sample bursts, scroll deferral and cancelling stale resize requests; existing UI QA checks settings round-trip, disclosure frame integrity and interrupted navigation.

## Acceptance criteria for 2.0 stable

- **Tap feedback:** each interactive button gives press-state feedback; radio/picker selection and disclosures have a transition; disabled or Reduce Motion states remain accessible.
- **Scroll:** native macOS inertial scrolling without involuntary jump to top/bottom; no forced window resize during the gesture.
- **Panel:** settings and system-details shrink/expand without old-frame clipping; repeated fast toggles do not flash, overlap or leave phantom scroll offsets.
- **Performance:** compare old 1.3.17 and 2.0 builds *on the same Mac* using Instruments (CPU, main-thread blocking, Core Animation FPS/hitches and memory) under idle/active/scroll/rapid-toggle workloads. Do not claim a fixed FPS until measured.
- **Reliability:** app memory and system disk storage units/values match macOS built-in tooling within metric-definition differences; test wake/sleep, SSD detach/reconnect, and hotplug.
- **Compatibility:** macOS 13+ and 26+ Liquid Glass, light/dark, high/standard refresh rate and Reduce Motion; keep original menu-bar alignment.

## Next implementation phases before stable

- Move remaining storage, network and per-application sampling subscriptions into a shared visibility-aware MonitoringCoordinator rather than binding `.task` lifetimes to cards; retain independent 1/2/5/10-second fast stream and 30-second capacity/SMART cadence.
- Break up the 900+ line MenuController into separate window geometry, navigation/interaction and menu presentation objects after the viewport scheduler is confirmed in the preview.
- Consolidate disclosure frame/height calculations (application rows and SSD details) to eliminate hard-coded deltas and cover animation interruption under changing monitor samples.
- Tune precise spring response and hover states from recorded real-Mac video and an Instruments trace; automated macOS builds alone cannot certify smooth frames.

## Building / manual QA

Download the **ChipBar CI artifact** for this branch, not a GitHub Release. Extract ChipBar.app outside Applications and quit stable ChipBar before launching. CI builds and tests run on GitHub; detailed interaction quality must be reviewed on the target Mac.

To exercise existing UI screenshots/QA, use the project's validated `--disclosure-only`, `--scroll-check` and settings round-trip harness where supported by `scripts/integration.py`.

Stats (https://github.com/exelban/stats) inspires the separation of Reader / Module / Popup / Widget. ChipBar does **not** copy its UI, binary code, or require its privileged helpers.
