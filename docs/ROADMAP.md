# Development Roadmap

## Guiding Principles

- **Get something on screen fast** — a visible, working panel on the Xeneon Edge is more motivating than a perfect architecture with no output
- **Iterate on the hard parts** — focus management and USB control are the highest-risk areas; validate them early
- **Build widgets incrementally** — start with a clock, then add system stats, then media controls
- **Document the protocol** — every USB HID discovery should be documented in this repo

## Phase 0: Foundation (Weeks 1–2)

**Goal:** A blank panel appears on the Xeneon Edge, doesn't steal focus, goes away cleanly.

- [x] Create Xcode project (macOS app, Swift, SwiftUI lifecycle with AppKit bridge)
- [x] Implement `LedgePanel` (NSPanel subclass with `.nonactivatingPanel`)
- [x] Detect the Xeneon Edge among connected screens (by resolution or name)
- [x] Display the panel fullscreen on the Xeneon Edge
- [ ] Verify non-focus-stealing behaviour (tap the panel, primary app stays focused) — blocked on touch remapping
- [x] Handle display connect/disconnect gracefully
- [x] Add a basic settings window on the primary display (display selection, quit button)
- [x] Build basic Clock widget (validates the widget system)
- [x] Build touch test view (tap counter with visual feedback)
- [x] Implement TouchRemapper (CGEventTap) to fix macOS touchscreen coordinate mapping
- [ ] Test and validate touch remapping end-to-end
- [ ] Disable App Sandbox in Xcode (`ENABLE_APP_SANDBOX = NO`) for CGEventTap
- [ ] Grant Accessibility permissions and verify touch calibration
- [ ] Set up the project structure:
  ```
  Ledge/
  ├── Ledge.xcodeproj
  ├── Sources/
  │   ├── App/
  │   │   ├── LedgeApp.swift          # App entry point
  │   │   └── AppDelegate.swift       # AppKit delegate for panel management
  │   ├── Display/
  │   │   ├── LedgePanel.swift        # NSPanel subclass
  │   │   ├── DisplayManager.swift    # Screen detection & management
  │   │   └── TouchRemapper.swift     # CGEventTap touch coordinate remapping
  │   ├── Layout/
  │   │   ├── LayoutEngine.swift      # Grid layout system
  │   │   └── LayoutModels.swift      # Data models
  │   ├── Widgets/
  │   │   ├── Protocol/
  │   │   │   └── LedgeWidget.swift   # Widget protocol
  │   │   ├── Runtime/
  │   │   │   ├── WidgetRegistry.swift
  │   │   │   ├── WidgetContext.swift
  │   │   │   └── WidgetContainer.swift
  │   │   └── BuiltIn/
  │   │       ├── ClockWidget/
  │   │       ├── CPUWidget/
  │   │       └── NowPlayingWidget/
  │   ├── Hardware/
  │   │   ├── USBHIDController.swift
  │   │   ├── DDCController.swift
  │   │   └── DeviceDiscovery.swift
  │   ├── DataProviders/
  │   │   ├── SystemDataProvider.swift
  │   │   ├── CPUProvider.swift
  │   │   ├── MemoryProvider.swift
  │   │   └── MediaProvider.swift
  │   └── Settings/
  │       ├── SettingsView.swift
  │       └── LayoutEditor.swift
  ├── Resources/
  │   └── Assets.xcassets
  ├── docs/                           # This directory
  └── Tests/
  ```

**Validation criteria:** Tap the black panel on the Xeneon Edge while typing in a text editor on the primary display. The text editor must remain focused.

## Phase 1: Layout & First Widgets (Weeks 3–4)

**Goal:** A configurable grid with a few working widgets.

- [ ] Implement the grid layout engine (12×3 default grid)
- [ ] Render grid lines / debug overlay (toggle-able)
- [ ] Implement `WidgetRegistry` and `WidgetContext`
- [ ] Build the **Clock** widget (simplest possible widget — validates the protocol)
- [ ] Build the **CPU Monitor** widget (validates system data providers)
- [ ] Build the **Now Playing** widget (validates media integration + touch controls)
- [ ] Implement widget placement from a JSON layout file
- [ ] Implement basic layout editing (drag widgets, resize, remove)
- [ ] Settings UI: widget picker, layout preview

**Validation criteria:** Three widgets visible on the Xeneon Edge. Tapping play/pause on the Now Playing widget controls music without switching focus.

## Phase 2: Hardware Control (Weeks 5–6)

**Goal:** Control the Xeneon Edge's brightness and colour settings from Ledge.

- [ ] Identify the Xeneon Edge's USB Product ID (run `ioreg` / `system_profiler` with device connected)
- [ ] Test DDC/CI brightness control (try MonitorControl or ddcctl first)
- [ ] If DDC/CI works: implement brightness/contrast sliders using MonitorControl's approach
- [ ] If DDC/CI doesn't work: investigate USB HID path
- [ ] Integrate the gist's colour control code into the architecture
- [ ] Build the **Display Controls** widget (brightness, contrast, colour temp sliders)
- [ ] Add a menubar item for quick brightness control (optional)

**Validation criteria:** Brightness slider on the Xeneon Edge changes the actual backlight brightness.

## Phase 3: Polish & Extended Widgets (Weeks 7–8)

**Goal:** A polished, daily-drivable application.

- [ ] Build the **Volume Control** widget (per-app volume)
- [ ] Build the **Weather** widget
- [ ] Build the **Shortcut Launcher** widget
- [ ] Implement multiple saved layouts (switch between "work", "gaming", "music")
- [ ] Implement a widget configuration panel in settings
- [ ] Add visual polish: widget animations, transitions, theme support
- [ ] Handle edge cases: display sleep/wake, screen resolution changes, orientation changes
- [ ] Performance profiling: ensure 60fps rendering, low CPU when idle
- [ ] Build as a signed, notarised .app for distribution

## Phase 4: USB Protocol Deep Dive (Ongoing)

**Goal:** Full understanding of the Corsair Xeneon Edge USB HID protocol.

- [ ] Set up Wireshark + USBPcap on a Windows machine
- [ ] Capture HID traffic for: brightness, contrast, colour balance, colour profile, OSD settings
- [ ] Document each HID report in `docs/USB_PROTOCOL.md`
- [ ] Implement full device control in Ledge
- [ ] Investigate: does iCUE send pixel data via USB for widgets, or does it render on the monitor?
- [ ] Investigate: are there firmware update commands?

## Phase 5: Plugin System (Future)

**Goal:** Third-party developers can build and distribute Ledge widgets.

- [ ] Define the stable public API for `LedgeWidget` protocol
- [ ] Build the `.ledgewidget` bundle format and loader
- [ ] Create a sample plugin project template
- [ ] Write developer documentation
- [ ] Build a plugin settings UI (install, enable/disable, permissions)
- [ ] Consider: plugin marketplace / registry (GitHub-based?)

## Phase 6: Community & Ecosystem (Future)

- [ ] Open source the project (licence TBD — likely MIT)
- [ ] Create a layout sharing mechanism (export/import JSON layouts)
- [ ] Build a **Web View** widget (iFrame equivalent)
- [ ] Investigate Linux support (the Xeneon Edge also has no Linux widget support)
- [ ] Home Assistant widget
- [ ] OBS widget
- [ ] Spotify widget (via Spotify API)

## Known Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| `.nonactivatingPanel` doesn't work properly with Xeneon Edge touch | Blocks the entire project | Test in Phase 0 before building anything else. **Status: Panel works, touch remapping in progress** |
| DDC/CI not supported by Xeneon Edge on macOS | Loses brightness control feature | Fall back to USB HID; investigate Corsair-specific protocol. **Status: DDC confirmed working via MonitorControl** |
| Apple changes IOKit HID access in future macOS | Breaks USB control | Follow MonitorControl project for updates; they face the same risk |
| macOS maps touchscreen to primary display (CONFIRMED) | Touch doesn't work on the correct screen | **Fixed with TouchRemapper** (CGEventTap-based coordinate remapping). Requires Accessibility permissions and disabled App Sandbox |
| Xeneon Edge touch input arrives as mouse events, not touch events (CONFIRMED) | No multi-touch gestures | Design widgets for single-tap interaction; multi-touch is not available via USB HID touchscreen on macOS |
| Plugin system security | Malicious plugins could access system data | Start with in-process plugins (trusted); add XPC sandboxing later |
| SwiftUI performance on 2560×720 at 60fps with many widgets | Janky animations | Profile early; use `Canvas` or Metal for heavy widgets if needed |
| CGEventTap requires Accessibility + no sandbox | Limits distribution options | Cannot use Mac App Store; distribute as notarised Developer ID app instead |

## Quick Wins for Motivation

If you want something visible and satisfying quickly:

1. **Day 1**: Create the Xcode project, create an `NSPanel`, display it fullscreen on the secondary display with a solid colour background and the text "Ledge" in the centre
2. **Day 2**: Add non-activating behaviour and verify it works with touch
3. **Day 3**: Add a clock widget
4. **Day 4**: Add a CPU usage widget
5. **Day 5**: Add Now Playing with touch controls

Five days to a working prototype that you'd actually want on your desk.
