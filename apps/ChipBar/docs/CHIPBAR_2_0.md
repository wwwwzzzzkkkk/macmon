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

## M5 Pro user testing: confirmed and follow-up corrections

The user has checked all six baseline interaction criteria on the first 2.0 preview: quick Settings/Back cycling, smooth System Details frame movement, native trackpad scrolling, updates during scroll, animated rings synchronized with numbers, and dark/light/Reduce Motion compatibility.

The next 2.0 preview preserves that tested motion baseline and addresses reported issues:

- **Every open resets ephemeral UI:** always return to monitoring (not Settings), app top three in CPU mode, System Details closed, SSD subdetails closed and power trend set to chip total. Actual preferences and sampling history are **not erased**. Existing `--apps`, `--apps-gpu`, `--apps-ane`, `--ssd-details` and `--system-details` QA command flags still work.
- **Hide system scroll indicator:** `NSScrollView.hasVerticalScroller = false`, while the native trackpad and momentum scrolling remain enabled. This avoids the bright white indicator obscuring the Liquid Glass edge.
- **Animated app metric selection:** 4-way CPU/GPU/Memory/ANE indicator moves with a spring and presses respond immediately. Ranking contents crossfade within a fixed height, so switching tabs does not resize the window or jolt scroll position.
- **Stable signing support:** by default GitHub builds still use ad-hoc signing. macOS can treat each rebuilt ad-hoc executable as a new code identity and ask for privacy permissions again; the program cannot and must not silently bypass the system prompt. Developers with a valid and persistent macOS code-signing certificate can use `CHIPBAR_CODESIGN_IDENTITY="Apple Development: ..." ./scripts/build.sh` to sign successive local builds with the same Team ID and bundle ID. This is **optional** and does not imply notarization or promise to eliminate all possible consent dialogs. Install/test the same app path, close old ChipBar instances first, and avoid changing the signing identity between builds. No accessibility/screen-capture privilege is requested by a normal ChipBar launch; synthetic mouse-automation QA explicitly needs existing event-posting permission.

## Known limitation: GitHub preview signing

The CI zip contains ad-hoc signed app code. Because its signed code identity can change with each CI run, TCC approvals may not carry over. Removing OS privacy prompts programmatically would be neither reliable nor appropriate. Use a consistent trusted signing identity for long-term iterative local testing, or accept OS prompts on a new CI build. If prompts continue on an unchanged build, capture the **exact prompt text and the executable requesting consent**, since they may originate from macOS, smartctl/macmon or an external path rather than ChipBar.

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
