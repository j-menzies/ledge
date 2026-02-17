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
| Web | ✅ Working | Embedded WKWebView — configurable URL. **Needs work:** touch scroll, swipe back/forward navigation |
| Home Assistant | ✅ Working | REST API integration, entity control (lights, covers, sensors). **Needs work:** faders/sliders for dimmable lights, custom display names for entities |
| System Performance | ✅ Working | CPU, memory, disk, network stats |
| System Audio | ✅ Working | Per-app volume control, input/output device switching. **Needs work:** larger touch targets for buttons |
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

### Touch Diagnostics & Testing Infrastructure

- [x] **TouchCoordinateMath** — extracted pure coordinate transformation functions (testable without live displays)
- [x] **TouchFlightRecorder** — ring buffer of last 500 touch events with device ID, coordinates, delivery status, latency
- [x] **TouchWatchdog** — independent 5-second timer monitoring CGEventTap health, auto-re-enables if silently disabled
- [x] **Delivery confirmation** — LedgePanel tracks received event count for drop detection
- [x] **Touch Diagnostics widget** (`com.ledge.touch-diagnostics`) — real-time pipeline health, stats, and event log
- [x] **Panel alignment bug fix** — `TouchRemapper.targetScreen` now updated on display rearrangement (was stale after screen config change)
- [x] **XCTest target** — unit tests for coordinate math (remap, CG↔Cocoa conversion, window-local transform)

### Touch Known Issues & Open Work

- [ ] **Stability:** Touch mapping occasionally drops or crashes — needs investigation. May be CGEventTap getting disabled under load, or the event tap thread timing out. Flight recorder + watchdog now provide diagnostic data
- [ ] **Focus stealing (CRITICAL):** Active application loses focus when touching the Edge. This is the #1 usability blocker. The `.nonactivatingPanel` + direct NSEvent delivery approach should prevent this, but something is still activating the app. Investigate: (a) `panel.makeKey()` in `mouseDown` — does this activate the app? (b) SwiftUI views that trigger `NSApp.activate()` internally, (c) WKWebView in the Web widget may activate the app on interaction, (d) NSAlert/NSMenu/system UI triggered by widget code. Needs systematic debugging with the Touch Diagnostics widget active
- [ ] **Mouse cursor guard:** When the mouse (not touch) drifts onto the Edge display, it can interact with widgets. Options: (a) invisible barrier that warps cursor back, (b) ignore mouse-sourced events on the Edge, (c) leave it for Web widget convenience. **Decision pending** — useful for Web widget but undesirable for everything else
- [ ] **Touch disable toggle:** Settings UI toggle to completely disable the touch event tap. Placed alongside the existing Event Tap settings. Useful for: (a) preventing accidental touches, (b) using mouse-only mode on the Edge, (c) troubleshooting touch issues. When disabled, the CGEventTap is torn down entirely — touchscreen events pass through to macOS as normal mouse events
- [ ] **Touch visual indicator:** Visual feedback when the screen is touched — ripple or highlight effect at touch point. Especially useful for buttons. May also show swipe direction/momentum for drag gestures
- [ ] **Long-running gestures:** Volume/progress slider drags work but need more testing for reliability
- [ ] **Event tap recovery:** If the CGEventTap is disabled by the system (timeout or user input), it re-enables — but need to verify touch state is properly reset. TouchWatchdog now detects and re-enables silently disabled taps
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
- [x] **Liquid Glass design language** — new default theme with frosted blur backgrounds, specular top-edge highlight (LinearGradient inner glow), drop shadow, 16pt continuous corner radius. Theme system extended with glass-specific properties (`glassInnerGlow`, `glassHighlightColor`, `glassShadowRadius`, `preferredBackgroundStyle`). Auto-enables blur when active. Classic themes preserved as alternatives
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

### Web Widget Improvements

- [ ] **Touch scroll support** — enable vertical scroll via touch drag within the WKWebView. Currently touch events are intercepted by TouchRemapper and delivered as click/drag, but the WKWebView needs proper scroll gesture forwarding
- [ ] **Swipe navigation** — swipe left-to-right triggers browser back, right-to-left triggers browser forward. Must coexist with the page-switching swipe gesture (page swipe is on the dashboard level; web swipe is within the widget). May need gesture disambiguation based on touch start location
- [ ] **Scroll position persistence** — remember scroll position across page switches / app restarts

### Home Assistant Widget Improvements

- [ ] **Faders/sliders for dimmable entities** — replace on/off toggle with a slider for lights that support brightness, colour temperature, or cover position. Use the HA `light.turn_on` service with `brightness_pct` parameter
- [ ] **Custom display names** — per-entity override of the display name in the widget. Stored in widget config. HA entity IDs are often cryptic (`light.hue_ambiance_lamp_1`); users should be able to rename to "Desk Lamp"
- [ ] **Entity grouping** — organise entities into groups/rooms within the widget (e.g., "Living Room", "Office")
- [ ] **RGB colour picker** — for lights that support colour, show a compact colour wheel or palette
- [ ] **Cover controls** — open/close/stop buttons + position slider for blinds and covers
- [ ] **Sensor display** — dedicated rendering for sensor entities (temperature, humidity, power) with sparkline history

### System Audio Widget Improvements

- [ ] **Larger button touch targets** — increase button sizes for reliable touch interaction on the Xeneon Edge (minimum 44pt, ideally 48pt+)
- [ ] **Visual feedback on tap** — highlight/scale animation when buttons are pressed

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

## Phase 6: Spotify Web API Integration 📋 PLANNED

**Goal:** Replace or supplement the AppleScript bridge with Spotify's Web API for cross-device playback visibility and control.

### Why

The AppleScript bridge only sees the local Spotify desktop app. The Web API shows playback on *any* device (phone, smart speaker, another computer) and enables cross-device control (transfer playback to Mac from phone, etc.). This also eliminates the NSAppleScript thread-safety crashes that plague the current bridge.

### Auth & Licensing

- **Auth flow:** Authorization Code with PKCE — no client secret, no backend server. Ledge spins up a temporary HTTP listener on `127.0.0.1:<port>`, opens browser for Spotify login, receives auth code, exchanges for tokens, caches refresh token for persistence
- **Classification:** Ledge is a **Non-Streaming SDA** (displays now-playing info, sends playback commands, but does not stream audio). Non-Streaming SDAs are permitted limited commercial use including App Store sales
- **Development Mode limits:** 5 authorised users, 1 Client ID, requires owner to have Spotify Premium. Sufficient for personal use and beta testing
- **Extended Quota Mode:** Required for public App Store distribution. Requires: registered business entity, 250,000 MAU, live launched service, operation in major Spotify markets. Apply when user base warrants it
- **Branding:** Must display Spotify attribution/logo per branding guidelines. Album art must link back to Spotify

### Implementation

- [ ] Create `SpotifyAuthManager` — PKCE flow, token storage in Keychain, automatic refresh
- [ ] Create `SpotifyAPIBridge` — Web API client for `/me/player`, `/me/player/devices`, playback control endpoints
- [ ] Device selector in Spotify widget — show active device, allow transfer
- [ ] "Playing on [device]" indicator when music is on another device
- [ ] Album art via URL (cleaner than extracting from local app)
- [ ] Keep AppleScript bridge as fallback for users without Spotify Premium or who prefer local-only
- [ ] Settings toggle: "Use Spotify Web API" vs "Use local Spotify app"
- [ ] Handle token expiry, network errors, and rate limiting gracefully

### Quota Strategy

1. **Phase 6 (now):** Development Mode — personal use + 5 beta testers
2. **Post-App Store launch:** Apply for Extended Quota once user base grows. Until approved, AppleScript bridge is the default; Web API is opt-in for users who register their own Spotify app (common pattern for open-source/indie Spotify integrations)

## Phase 7: Licensing & Commercial Distribution (Paddle) 📋 FUTURE

**Goal:** Sell Ledge as a paid macOS app via direct distribution, using Paddle for payment processing, license key generation, and in-app license validation.

### Why Paddle

CGEventTap and USB HID access require App Sandbox to be disabled, which **prevents Mac App Store distribution**. Paddle provides the full commerce stack for direct-distributed Mac apps: payment processing (including VAT/GST), license key generation and validation, a native macOS SDK for in-app licensing, and a seller dashboard for analytics and customer management.

### Paddle Account & Product Setup

- [ ] **Create Paddle seller account** — complete identity verification, tax information, payout details
- [ ] **Create product** in Paddle dashboard — set pricing, currency, description
- [ ] **Configure license key settings** — activations per key (e.g., 2 Macs per license), expiry policy (perpetual vs annual), deactivation rules
- [ ] **Configure trial settings** — 14-day trial, full functionality, no payment required to start
- [ ] **Tax setup** — Paddle handles VAT/GST as Merchant of Record (they sell on your behalf and remit taxes)
- [ ] **Webhook endpoints** (optional) — for order notifications, subscription events, refund alerts

### Paddle SDK Integration (In-App)

- [ ] **Add Paddle macOS SDK** — SPM or manual framework embedding. SDK handles: license activation window, trial management, purchase flow (opens Paddle checkout), license validation (online + offline grace period)
- [ ] **License check at launch** — in `AppDelegate.applicationDidFinishLaunching`, before showing the panel:
  1. Initialise Paddle SDK with product ID and vendor credentials
  2. Check license state: `.activated`, `.trial`, `.trialExpired`, `.deactivated`
  3. If `.activated` → proceed to normal app launch
  4. If `.trial` → show trial banner (days remaining) on Settings window, proceed to normal launch
  5. If `.trialExpired` or `.deactivated` → show Paddle licensing window (purchase/activate), block panel display until resolved
- [ ] **Trial implementation** — 14-day full-functionality trial. Show remaining days in Settings header. "Buy Now" button always visible in Settings during trial. After expiry, app shows activation-required screen with purchase and license key entry
- [ ] **Activation flow** — user enters license key in-app → Paddle SDK validates against their server → activates on this machine. Also support "Buy" button that opens Paddle checkout in browser → auto-activates after purchase
- [ ] **Deactivation** — allow users to deactivate a license from one Mac to move it to another (Settings > License > Deactivate). Paddle SDK handles this
- [ ] **Offline grace period** — if the Mac is offline, Paddle SDK uses cached validation. Configure grace period (e.g., 30 days) before requiring online re-validation
- [ ] **License status in Settings** — dedicated "License" section showing: license state, email, activation count, expiry (if applicable), Deactivate/Manage buttons

### Trial & Purchase UX

- [ ] **First launch (no license)** — onboarding flow starts trial automatically. No friction. User sees "14-day trial — enjoy full access" in Settings header
- [ ] **During trial** — subtle persistent banner in Settings: "Trial: X days remaining — [Buy Now]". Full app functionality. No nag dialogs interrupting use
- [ ] **Trial expired** — app launches to a licensing screen (not the dashboard). Clear messaging: "Your trial has ended. Purchase Ledge to continue." Two options: enter license key, or purchase (opens Paddle checkout). Dashboard and panel are hidden until activated
- [ ] **Post-purchase** — "Thank you" confirmation. License section in Settings shows activated status. Banner disappears. App is fully unlocked permanently (or until subscription renewal, if using subscriptions)
- [ ] **Pricing model decision** — one-time purchase (simpler, users prefer it) vs annual subscription (recurring revenue, funds ongoing development). Paddle supports both. **Recommendation: one-time purchase with major-version paid upgrades** — friendlier for a hardware companion app that users expect to "just work"

### Website & Landing Page

- [ ] **Domain** — register `ledge.app` or `getledge.app` or similar
- [ ] **Landing page** — hero image/video of Ledge on the Xeneon Edge, feature highlights, screenshots, pricing, download button, Paddle "Buy Now" button
- [ ] **Download page** — DMG download link, system requirements (macOS 14+, Corsair Xeneon Edge), version history
- [ ] **Support page** — FAQ (permissions, troubleshooting, license transfer), contact email
- [ ] **Privacy Policy** — required by Paddle, Apple notarisation, and API integrations (Spotify, WeatherKit). Disclose: no personal data collected beyond license activation, analytics if any, third-party services used
- [ ] **Terms of Service / EULA** — license grant, usage restrictions, warranty disclaimer
- [ ] **Static site generator** — use something lightweight (Hugo, Astro, or just plain HTML). Host on Vercel, Netlify, or GitHub Pages

### Code Signing, Notarisation & Packaging

- [ ] **Apple Developer Program** — enrol ($99/year) for Developer ID certificate
- [ ] **Code signing** — sign with Developer ID Application certificate
- [ ] **Hardened Runtime** — enable with entitlements: Accessibility, Input Monitoring
- [ ] **Notarisation** — submit to Apple via `notarytool`, staple the ticket to the app
- [ ] **DMG packaging** — branded DMG with background image, drag-to-Applications arrow, Retina-ready icons. Use `create-dmg` or similar tool
- [ ] **Automated build pipeline** — script or CI (GitHub Actions): `xcodebuild archive` → sign → notarise → staple → create DMG → upload to website + Paddle
- [ ] **Sparkle auto-update** — integrate Sparkle framework for delta updates. Host appcast.xml on the website. Ed25519 signing for update integrity

## Phase 8: App Hardening & Reliability 📋 FUTURE

**Goal:** Production-quality reliability, error handling, and polish for paying customers.

### First-Run Experience

- [ ] **Onboarding flow** — guided setup wizard: detect Xeneon Edge, grant Accessibility permission, calibrate touch, choose theme, select initial widgets. Runs on first launch or when no Xeneon Edge is detected
- [ ] **Graceful degradation** — work without Accessibility (no touch remapping, mouse-only mode), without Xeneon Edge (preview mode on primary display), without network (offline widgets only)
- [ ] **Permission health check** — Settings panel showing status of all required permissions with "Fix" buttons that open System Settings to the correct pane

### Error Recovery & Crash Resilience

- [ ] **CGEventTap recovery** — auto-restart on failure, reconnect to display on wake
- [ ] **Corrupt data recovery** — detect and recover from corrupt layout JSON, widget config, or preferences. Fall back to defaults with user notification
- [ ] **Crash reporting** — lightweight crash reporter (Sentry, or custom signal handler writing to `~/Library/Application Support/Ledge/crashes/`). Include: crash stack, last flight recorder entries, widget state
- [ ] **Watchdog for widget hangs** — detect widgets that block the main thread for >2s, force-reload them

### Security & Data

- [ ] **Keychain storage** — move all tokens and credentials (Spotify, Home Assistant, Paddle license) from UserDefaults/files to macOS Keychain
- [ ] **Input validation** — sanitise all user inputs (widget config, URLs for Web widget, Home Assistant endpoints)
- [ ] **Memory & CPU budgets** — per-widget resource limits, pause widgets that exceed thresholds

### Performance

- [ ] **Profiling** — target 60fps rendering, <5% CPU when idle, <200MB memory
- [ ] **Instruments profiling** for memory leaks, especially in long-running widget timers and album art caching
- [ ] **Stress testing** — 10+ widgets active, rapid page switching, sleep/wake cycles, display disconnect/reconnect
- [ ] **Launch time** — target <2s to panel visible

### Accessibility & Polish

- [ ] **VoiceOver labels** for Settings UI, keyboard navigation in Settings
- [ ] **Layout sharing** — export/import JSON files for sharing widget layouts
- [ ] **Versioning** — semantic versioning, release notes, changelog displayed in Settings

### Legal & Compliance

- [ ] **Privacy Policy** (required for notarisation, Paddle, and API integrations)
- [ ] **Spotify branding compliance** — attribution, logo usage, content linking per Spotify Developer Terms
- [ ] **Home Assistant attribution** if applicable
- [ ] **WeatherKit attribution** requirements
- [ ] **EULA / Terms of Service** — bundled with DMG and displayed on first launch

---

## Known Risks

| Risk | Impact | Status |
|------|--------|--------|
| `.nonactivatingPanel` + touch focus | Blocks the project | **Mostly resolved** — direct NSEvent delivery prevents focus stealing. Edge cases remain |
| DDC/CI on macOS | Brightness control | **DDC confirmed working** via MonitorControl |
| macOS touchscreen → primary display mapping | Touch on wrong screen | **Fixed** — TouchRemapper intercepts and remaps coordinates |
| Touch arrives as mouse events, not NSTouch | No multi-touch | **Confirmed** — design for single-point interaction only |
| CGEventTap stability under load | Touch drops out | **Observed** — tap can be disabled by timeout; auto-re-enable implemented but needs more testing |
| CGEventTap requires Accessibility + no sandbox | No Mac App Store | Distribute as notarised Developer ID app. Investigate XPC helper for App Store path |
| Spotify Extended Quota requirements | Web API limited to 5 users in Dev Mode | AppleScript bridge as default, Web API opt-in. Apply for Extended Quota at scale |
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
