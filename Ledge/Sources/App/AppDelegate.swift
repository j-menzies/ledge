import AppKit
import SwiftUI
import os.log

/// AppKit delegate that manages the LedgePanel lifecycle.
///
/// The AppDelegate is responsible for:
/// 1. Creating the DisplayManager, LayoutManager, WidgetConfigStore, and ThemeManager
/// 2. Detecting the Xeneon Edge on launch
/// 3. Registering built-in widgets
/// 4. Creating and displaying the widget panel
/// 5. Managing the system tray icon and settings window
class AppDelegate: NSObject, NSApplicationDelegate {

    private let logger = Logger(subsystem: "com.ledge.app", category: "AppDelegate")

    /// The display manager — shared with the settings UI via @EnvironmentObject.
    let displayManager = DisplayManager()

    /// The layout manager — manages active layout and persistence.
    let layoutManager = LayoutManager()

    /// The widget config store — per-instance config persistence.
    let configStore = WidgetConfigStore()

    /// The theme manager — controls visual theme across dashboard and settings.
    let themeManager = ThemeManager()

    /// System tray status item.
    private var statusItem: NSStatusItem?

    /// Observer for settings window visibility changes.
    private var windowObservers: [Any] = []

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("Ledge starting up...")

        // Register all built-in widgets
        WidgetRegistry.shared.registerBuiltInWidgets()

        // Create the system tray icon
        setupStatusItem()

        // Attempt to detect the Xeneon Edge and show the panel
        displayManager.detectXenonEdge()

        if displayManager.xeneonScreen != nil {
            // Determine which permissions active widgets need. Request them
            // upfront so system dialogs are dismissed before the fullscreen
            // transition — this prevents dialogs from interfering with the
            // menu-bar-hiding fullscreen helper.
            let requiredPerms = requiredWidgetPermissions()

            displayManager.showPanelWhenReady(requiredPermissions: requiredPerms) { [weak self] in
                guard let self else { return }

                // Configure panel transparency for blur/image backgrounds
                self.configurePanelTransparency()

                let dashboardView = DashboardView(
                    layoutManager: self.layoutManager,
                    configStore: self.configStore,
                    registry: WidgetRegistry.shared
                )
                .environmentObject(self.displayManager)
                .environment(self.themeManager)
                self.displayManager.setPanelContent(dashboardView)

                // Start touch remapper — suppresses wrongly-mapped mouse events from the
                // Edge touchscreen and posts synthetic events at the correct Edge position.
                self.displayManager.startTouchRemapper()

                self.logger.info("Panel displayed on Xeneon Edge")
            }
        } else {
            logger.warning("Xeneon Edge not found on launch — panel not shown")
        }

        // Start as .accessory (hidden from Dock/CMD+TAB) then observe window changes
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.accessory)
            NSApp.activate(ignoringOtherApps: true)
            self.observeSettingsWindow()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        logger.info("Ledge shutting down")
        layoutManager.save()
        displayManager.stopTouchRemapper()
        displayManager.destroyPanel()
    }

    /// Keep the app running when all windows are closed (the panel is still active).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - System Tray

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "rectangle.split.3x1", accessibilityDescription: "Ledge")
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "Show Settings", action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(.separator())

        let panelItem = NSMenuItem(title: "Toggle Panel", action: #selector(togglePanel), keyEquivalent: "")
        menu.addItem(panelItem)
        menu.addItem(.separator())

        menu.addItem(withTitle: "Quit Ledge", action: #selector(quitApp), keyEquivalent: "q")

        statusItem?.menu = menu
    }

    @objc private func showSettings() {
        // Show in Dock and CMD+TAB while settings is open
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // Find the settings window created by the SwiftUI Window scene.
        // It's the titled, non-panel window.
        for window in NSApp.windows {
            if window.styleMask.contains(.titled)
                && !(window is LedgePanel)
                && !(window is FullscreenHelperWindow) {
                window.makeKeyAndOrderFront(nil)
                return
            }
        }
    }

    // MARK: - Settings Window Observation

    /// Watch for the settings window being closed so we can hide from CMD+TAB.
    private func observeSettingsWindow() {
        // Observe any window closing — check if it was the settings window
        let closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let window = notification.object as? NSWindow,
                  window.styleMask.contains(.titled),
                  !(window is LedgePanel),
                  !(window is FullscreenHelperWindow) else { return }
            self?.logger.info("Settings window closed — hiding from CMD+TAB")
            // Delay slightly to let the window fully close
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self?.updateActivationPolicy()
            }
        }
        windowObservers.append(closeObserver)

        // Also observe window ordering out (minimize, etc.)
        let orderOutObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMiniaturizeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let window = notification.object as? NSWindow,
                  window.styleMask.contains(.titled),
                  !(window is LedgePanel),
                  !(window is FullscreenHelperWindow) else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self?.updateActivationPolicy()
            }
        }
        windowObservers.append(orderOutObserver)
    }

    /// Check if any settings windows are visible and update the activation policy accordingly.
    private func updateActivationPolicy() {
        let hasVisibleSettingsWindow = NSApp.windows.contains { window in
            window.styleMask.contains(.titled)
            && !(window is LedgePanel)
            && !(window is FullscreenHelperWindow)
            && window.isVisible
            && !window.isMiniaturized
        }

        if hasVisibleSettingsWindow {
            NSApp.setActivationPolicy(.regular)
        } else {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    @objc private func togglePanel() {
        if displayManager.isActive {
            displayManager.hidePanel()
        } else {
            displayManager.showPanel()
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - Panel Configuration

    /// Configure the panel's opacity based on the current background settings.
    /// Blur and Transparent widget styles require a non-opaque panel so the
    /// desktop wallpaper or background image shows through gaps between widgets.
    /// Solid mode keeps the panel opaque for best performance.
    private func configurePanelTransparency() {
        let needsTransparency = themeManager.widgetBackgroundStyle != .solid
        displayManager.panel?.setTransparent(needsTransparency)
    }

    // MARK: - Permission Helpers

    /// Collect the set of permissions required by widgets in the active layout.
    private func requiredWidgetPermissions() -> Set<WidgetPermission> {
        var perms = Set<WidgetPermission>()
        for placement in layoutManager.activeLayout.placements {
            if let descriptor = WidgetRegistry.shared.registeredTypes[placement.widgetTypeID] {
                perms.formUnion(descriptor.requiredPermissions)
            }
        }
        return perms
    }
}
