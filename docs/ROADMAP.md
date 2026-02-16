# Development Roadmap

*Last updated: February 2026*

## Guiding Principles

- **Get something on screen fast** — a visible, working panel on the Xeneon Edge is more motivating than a perfect architecture with no output
- **Iterate on the hard parts** — focus management and USB control are the highest-risk areas; validate them early
- **Build widgets incrementally** — start with a clock, then add system stats, then media controls
- **Document the protocol** — every USB HID discovery should be documented in this repo
- **Touch must be transparent** — interaction on the Edge must never interfere with the primary display, cursor, or foreground application

---

## Phase 0: Foundation ✅ COMPLETE

**Goal:** A blank panel appears on the Xeneon Edge, doesn't steal focus, goes away cleanly.

- [x] Create Xcode project (macOS app, Swift, SwiftUI lifecycle with AppKit bridge)
- [x] Implement `LedgePanel` (NSPanel subclass with `.nonactivatingPanel`)
- [x] Detect the Xeneon Edge among connected screens (by resolution or name)
- [x] Display the panel fullscreen on the Xeneon Edge
- [x] Handle display connect/disconnect gracefully
- [x] Add settings window on the primary display (NavigationSplitView with sidebar)
- [x] Build basic Clock widget (validates the widget system)
- [x] Build touch test view
- [x] Implement TouchRemapper (CGEventTap) to fix macOS touchscreen coordinate mapping
- [x] Auto-detect touchscreen device via IOKit HID (HIDTouchDetector) — eliminates manual calibration
- [x] App Sandbox disabled (`ENABLE_APP_SANDBOX = NO`)
- [x] Accessibility permission request/polling flow with auto-retry
- [x] Display security: blank panel on sleep/lock/screensaver, restore on unlock/wake

**Validation:** Panel renders on the Xeneon Edge. Touch events are intercepted and remapped. Focus does not leave the primary display (mostly — see Touch Known Issues).

## Phase 1: Layout & Core Widgets ✅ COMPLETE

**Goal:** A configurable grid with working widgets.

- [x] Implement 20×6 grid layout engine (`GridRenderer`, `LayoutManager`, `LayoutModels`)
- [x] `WidgetRegistry` singleton with type registration and view factories
- [x] `WidgetContext` per-instance with size and config store
- [x] `WidgetConfigStore` for per-widget persistent configuration (JSON)
- [x] Widget placement from JSON layout files (`~/Library/Application Support/Ledge/`)
- [x] Layout editing: interactive grid editor in Settings with drag, resize, remove
- [x] Settings UI: widget picker (gallery with cards, categories, search), layout preview
- [x] Multiple saved layouts with create/switch/delete (LayoutManager)
- [x] Layout migration (auto-scales old 10×3 layouts to 20×6)
- [x] Theme system: 5 built-in themes (Dark, Light, Midnight, Ocean, Forest), auto mode

### Built-in Widgets (10)

| Widget | Status | Notes |
|--------|--------|-------|
| Clock | ✅ Working | Simple analog/digital clock |
| DateTime | ✅ Working | Date and time display |
| Spotify | ✅ Working | AppleScript bridge, album art, playback controls, volume, progress seek, album colour extraction, marquee text, text reveal animation |
| Calendar | ✅ Working | macOS EventKit integration. **Needs work:** respects visible/selected calendars only; shared calendars leak through |
| Weather | ✅ Working | CoreLocation + WeatherKit |
| Web | ✅ Working | Embedded WKWebView — configurable URL |
| Home Assistant | ✅ Working | REST API integration, entity control (lights, covers, sensors) |
| System Performance | ✅ Working | CPU, memory, disk, network stats |
| System Audio | ✅ Working | Per-app volume control, input/output device switching |
| Google Meet | ✅ Working | AppleScript hook to Chrome — mic/camera toggle, meeting detection |

## Phase 2: Touch Refinement 🔄 IN PROGRESS

**Goal:** Touch on the Xeneon Edge is completely transparent — no cursor movement, no focus changes, no interference with the primary display. Reliable under all conditions.

### Current Approach: Direct NSEvent Delivery

The TouchRemapper intercepts ALL mouse events from the touchscreen via a CGEventTap, returns `nil` to suppress them from the OS entirely, then constructs NSEvents with correct Xeneon Edge coordinates and delivers them directly to the LedgePanel via `sendEvent()`. Events never re-enter the window server.

- [x] CGEventTap intercepts touchscreen events (identified by HID device ID)
- [x] Coordinate remapping from primary display CG space to Edge CG space
- [x] Suppress original events (return nil from callback)
- [x] Direct NSEvent delivery to LedgePanel (bypasses window server)
- [x] Asynchronous delivery via `DispatchQueue.main.async` (avoids run loop deadlock)
- [x] `NSApp.preventWindowOrdering()` before each delivery
- [x] mouseMoved suppression (touchscreen hover noise)
- [x] Diagnostic logging at `.notice` level with sequence IDs
- [x] Automatic permission polling + re-request on app activation

### Touch Known Issues & Open Work

- [ ] **Stability:** Touch mapping occasionally drops or crashes — needs investigation. May be CGEventTap getting disabled under load, or the event tap thread timing out
- [ ] **Focus leakage:** Mostly fixed with direct delivery, but edge cases remain. Goal is zero focus interference under all circumstances
- [ ] **Mouse cursor guard:** When the mouse (not touch) drifts onto the Edge display, it can interact with widgets. Options: (a) invisible barrier that warps cursor back, (b) ignore mouse-sourced events on the Edge, (c) leave it for Web widget convenience. **Decision pending** — useful for Web widget but undesirable for everything else
- [ ] **Touch disable toggle:** Settings UI toggle to completely disable the touch event tap. Placed alongside the existing Event Tap settings. Useful for: (a) preventing accidental touches, (b) using mouse-only mode on the Edge, (c) troubleshooting touch issues. When disabled, the CGEventTap is torn down entirely — touchscreen events pass through to macOS as normal mouse events
- [ ] **Long-running gestures:** Volume/progress slider drags work but need more testing for reliability
- [ ] **Event tap recovery:** If the CGEventTap is disabled by the system (timeout or user input), it re-enables — but need to verify touch state is properly reset
- [ ] **Multi-touch:** Not available on macOS via USB touchscreen — single-point only. Design all widgets for single-tap/drag interaction
- [ ] **Comprehensive testing:** Systematic test plan needed — tap, drag, rapid taps, app switching during touch, sleep/wake with active touch, display disconnect during touch
- [ ] **Separate Spaces per display:** macOS "Displays have separate Spaces" setting may break fullscreen panel behaviour on the Xeneon Edge. Needs systematic testing — panel visibility, Space switching, Mission Control interaction, fullscreen apps on primary display

## Phase 3: Visual Polish & UX 📋 NEXT UP

**Goal:** A visually polished, daily-drivable application with refined transitions and a cohesive design language.

### Spotify Widget Polish

- [x] Album art crossfade/fade-out-in on track change, synchronised with background colour transition
- [x] Centered playback controls with 44pt touch targets
- [x] Larger text fonts for touchscreen readability
- [x] Marquee text with overflow threshold fix (no scroll when text fits)
- [x] Left-to-right text reveal animation on track change

### Visual Design

- [x] **Transparent widget backgrounds with blur** — `NSVisualEffectView` integration via `VisualEffectBlur` SwiftUI wrapper. Three widget background modes: Solid, Blur, Transparent. Configurable in Settings > Appearance
- [ ] **Liquid Glass design language** — adopt Apple's vibrancy, blur materials, glass-effect borders. Architectural change to the theme system
- [x] **Background images** — configurable wallpapers behind the widget grid via Settings > Appearance. Supports any image file; recommends 2560×720 for Xeneon Edge. Corsair iCUE wallpapers work well
- [ ] **Widget transitions** — smooth animations when switching layouts, adding/removing widgets

### Multiple Pages (Swipeable Layouts)

- [x] Page indicator on the Edge (dot-style capsule, fades in on page switch, subtle at rest)
- [x] Swipe gesture to switch between saved layouts (dampened drag + threshold, wraps around)
- [x] `LayoutManager` page navigation: `nextPage()`, `previousPage()`, `switchToPage(_:)`, `activePageIndex`, `pageCount`
- [ ] Optional auto-rotation on timer
- [ ] Per-page background image support
- [ ] Settings UI for page ordering and management

**Note:** `LayoutManager` already supports multiple saved layouts with create/switch/delete. Pages are now swipeable on the Edge with a visual indicator.

### Widget Gallery Improvements

- [x] Visual card-based gallery with 2-column grid
- [x] Category filtering (Media, Productivity, System, Smart Home, Info, Web)
- [x] Search bar
- [x] "Already added" badges
- [x] Hover effects and category-coloured icons
- [ ] Widget preview thumbnails (render a small snapshot of each widget)
- [ ] Widget configuration from the layout editor (tap a placed widget → settings popover)

## Phase 4: New Widgets 📋 PLANNED

### App Launcher (Stream Deck Style)

A grid of configurable buttons, each occupying one grid cell. Like a digital Stream Deck built into the Edge display.

- [ ] Configurable button grid — each button is one layout grid cell
- [ ] Per-button configuration: app to launch, system action, keyboard shortcut, URL, or script
- [ ] Button appearance: custom icon (SF Symbols or image), label, background colour
- [ ] Transparent glass-effect button background (consistent with Liquid Glass theme)
- [ ] Press animation (scale/highlight feedback for touch)
- [ ] App launching via `NSWorkspace.shared.open()` / `Process` for scripts
- [ ] Investigate Stream Deck SDK compatibility for shared configurations
- [ ] Folder/group support (tap to expand a group of related buttons)

### MS Teams Integration

Hook into the Microsoft Teams PWA (Progressive Web App running in browser) for meeting controls, similar to the existing Google Meet widget.

- [ ] Detect active Teams meeting in the PWA (AppleScript to browser)
- [ ] Mic mute/unmute toggle
- [ ] Camera on/off toggle
- [ ] Visual indicator for screen sharing (bold flashing border around a widget)
- [ ] Meeting status display (in meeting / not in meeting / presenting)
- [ ] Also investigate the full MS Teams desktop client (different approach may be needed)

### Calendar Improvements

- [ ] **Respect visible calendars only** — filter out shared/subscribed calendars the user has hidden in macOS Calendar
- [ ] **Meeting type detection** — identify Google Meet and MS Teams meeting links in calendar events
- [ ] **Meeting quick-join** — one-tap join for detected meeting types (opens Meet/Teams URL)
- [ ] **Meeting controls integration** — when in a detected meeting, show mic/camera toggles inline
- [ ] **Screen sharing indicator** — visual feedback (e.g., flashing border) when screen is being shared
- [ ] **Google Calendar direct integration** — OAuth-based REST API as an alternative/supplement to macOS EventKit. Gives full control over which calendars are visible, avoids the shared calendar leak issue. **Large effort** — requires OAuth flow, token management, refresh handling

### Other Widget Ideas

- [ ] OBS Studio widget (scene switching, stream status)
- [ ] Network monitor (bandwidth, latency, connected devices)
- [ ] Clipboard history
- [ ] Countdown timer / Pomodoro
- [ ] Notes / sticky notes
- [ ] System shortcuts (sleep, lock, screenshot, Do Not Disturb toggle)

## Phase 5: Hardware Control 📋 PLANNED

**Goal:** Control the Xeneon Edge's brightness and colour settings from Ledge.

- [ ] Test DDC/CI brightness control (DDC confirmed working via MonitorControl)
- [ ] Implement brightness/contrast sliders
- [ ] Investigate Corsair-specific USB HID protocol for colour profiles
- [ ] Build a **Display Controls** widget
- [ ] Set up Wireshark + USBPcap on Windows for protocol capture
- [ ] Document HID reports in `docs/USB_PROTOCOL.md`
- [ ] Investigate: does iCUE send pixel data via USB, or render on-monitor?

## Phase 6: Distribution & Community 📋 FUTURE

- [ ] Build as a signed, notarised .app for distribution
- [ ] Performance profiling: 60fps rendering, low CPU when idle
- [ ] Open source (licence TBD — likely MIT)
- [ ] Layout sharing (export/import JSON)
- [ ] Investigate Linux support
- [ ] Plugin system assessment — currently keeping widgets built-in for simplicity. Revisit if community demand warrants it

---

## Known Risks

| Risk | Impact | Status |
|------|--------|--------|
| `.nonactivatingPanel` + touch focus | Blocks the project | **Mostly resolved** — direct NSEvent delivery prevents focus stealing. Edge cases remain |
| DDC/CI on macOS | Brightness control | **DDC confirmed working** via MonitorControl |
| macOS touchscreen → primary display mapping | Touch on wrong screen | **Fixed** — TouchRemapper intercepts and remaps coordinates |
| Touch arrives as mouse events, not NSTouch | No multi-touch | **Confirmed** — design for single-point interaction only |
| CGEventTap stability under load | Touch drops out | **Observed** — tap can be disabled by timeout; auto-re-enable implemented but needs more testing |
| CGEventTap requires Accessibility + no sandbox | No Mac App Store | Distribute as notarised Developer ID app |
| SwiftUI performance at 2560×720 | Janky animations | Not yet profiled — monitor as widget count grows |
| Plugin system security | Malicious code | **Deferred** — keeping widgets built-in for now |
| Mouse cursor wandering onto Edge | Unintended widget interaction | **Under consideration** — useful for Web widget, problematic otherwise |
| "Displays have separate Spaces" setting | Panel may not show on Edge, Space switching issues | **Untested** — needs investigation with the setting enabled |

---

## Architecture Reference

### Project Structure (Current)

```
Ledge/
├── Ledge.xcodeproj
├── Sources/
│   ├── App/
│   │   ├── LedgeApp.swift              # @main entry, SwiftUI App lifecycle
│   │   ├── AppDelegate.swift           # NSApplicationDelegate, panel/touch lifecycle
│   │   ├── DashboardView.swift         # Root view on Xeneon Edge
│   │   └── ThemeManager.swift          # Theme system (5 themes, auto mode)
│   ├── Display/
│   │   ├── LedgePanel.swift            # NSPanel subclass (.nonactivatingPanel)
│   │   ├── DisplayManager.swift        # Edge detection, panel lifecycle, permissions
│   │   ├── TouchRemapper.swift         # CGEventTap → direct NSEvent delivery
│   │   └── HIDTouchDetector.swift      # IOKit USB touchscreen auto-detection
│   ├── Layout/
│   │   ├── GridRenderer.swift          # Grid rendering on Edge
│   │   ├── LayoutManager.swift         # Multi-layout management, persistence
│   │   └── LayoutModels.swift          # WidgetLayout, WidgetPlacement (Codable)
│   ├── Widgets/
│   │   ├── Protocol/
│   │   │   └── LedgeWidget.swift       # WidgetDescriptor, WidgetContext, GridSize
│   │   ├── Runtime/
│   │   │   ├── WidgetRegistry.swift     # Singleton, registers/creates widget views
│   │   │   └── WidgetConfigStore.swift  # Per-widget persistent configuration
│   │   └── BuiltIn/
│   │       ├── CalendarWidget/
│   │       ├── ClockWidget/
│   │       ├── DateTimeWidget/
│   │       ├── GoogleMeetWidget/
│   │       ├── HomeAssistantWidget/
│   │       ├── SpotifyWidget/
│   │       ├── SystemAudioWidget/
│   │       ├── SystemPerformanceWidget/
│   │       ├── WeatherWidget/
│   │       └── WebWidget/
│   ├── Settings/
│   │   └── SettingsView.swift          # Full settings UI (display, widgets, layout, appearance)
│   └── Hardware/                        # Stubs for Phase 5
├── Assets.xcassets/
└── docs/
    ├── OVERVIEW.md
    ├── ARCHITECTURE.md
    ├── FOCUS_MANAGEMENT.md
    ├── WIDGET_SYSTEM.md
    ├── USB_PROTOCOL.md
    ├── ROADMAP.md                       # This file
    └── XCODE_SETUP.md
```

### Key Technical Facts

- **Target**: macOS 14+ (Sonoma), Swift 5.9+
- **Xeneon Edge**: 2560×720, 32:9, 60Hz, 5-point multi-touch (single-point on macOS)
- **Grid**: 20 columns × 6 rows (each cell ≈128×120pt)
- **Touch pipeline**: CGEventTap (suppress) → NSEvent (construct) → LedgePanel.sendEvent() (deliver async)
- **App Sandbox**: DISABLED — required for CGEventTap and USB HID
- **Permissions**: Accessibility (CGEventTap), Input Monitoring (HID, Phase 5)
- **Persistence**: `~/Library/Application Support/Ledge/` (JSON)
- **USB**: Corsair VID `0x1B1C`, Touchscreen PID `0x0859`
