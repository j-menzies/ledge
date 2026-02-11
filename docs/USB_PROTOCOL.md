# USB Protocol & Hardware Control

## Overview

The Corsair Xeneon Edge connects to a computer via:
1. **Video signal**: USB-C (DisplayPort Alt Mode) or HDMI — this is the display path
2. **USB data**: USB-C — this provides touch input, and (on Windows) the HID control channel that iCUE uses for brightness, colour, and firmware communication

On macOS, the video path works natively. Touch input works (as standard mouse events). But the USB HID control channel used by iCUE for device settings has no macOS support.

## Two Control Approaches

Ledge will pursue two complementary approaches to controlling the Xeneon Edge's display settings:

### Approach 1: DDC/CI over I²C

DDC/CI (Display Data Channel Command Interface) is a VESA standard that allows a computer to send commands to a monitor over the display cable (HDMI, DisplayPort, USB-C DP Alt). It's the standard way to control brightness, contrast, volume, and other settings on external monitors.

**Advantages:**
- Well-documented standard (VESA MCCS)
- Proven macOS implementations exist (MonitorControl, Lunar, BetterDisplay)
- Works over the display connection, no separate USB HID needed
- Supports: brightness, contrast, volume, input source, colour preset, power state

**Challenges on macOS:**
- Apple doesn't officially expose DDC/CI APIs
- On Intel Macs, the approach used IOKit `IOFramebufferI2CInterface` (private-ish API)
- On Apple Silicon, the kernel changed — `IOFramebuffer` became `IOMobileFramebuffer`, and old I²C methods stopped working
- MonitorControl and BetterDisplay have found workarounds for Apple Silicon, but they involve reverse-engineered IOKit paths

**Implementation plan:**
1. Reference MonitorControl's DDC implementation (open source, Swift, MIT licence)
2. Use their `DDC.swift` module (or equivalent) to send MCCS commands
3. Support at minimum: brightness (VCP code 0x10), contrast (0x12), audio volume (0x62)
4. Test specifically with the Xeneon Edge — some monitors have quirky DDC implementations

```swift
// Conceptual DDC control interface
protocol DisplayControl {
    func getBrightness() async throws -> UInt16
    func setBrightness(_ value: UInt16) async throws
    func getContrast() async throws -> UInt16
    func setContrast(_ value: UInt16) async throws
    func getVolume() async throws -> UInt16
    func setVolume(_ value: UInt16) async throws
}
```

### Approach 2: USB HID (Corsair-Proprietary)

Corsair uses a proprietary USB HID protocol to communicate with the Xeneon Edge for features beyond standard DDC/CI. On Windows, iCUE uses this channel for:
- Colour profile management (the gist you wrote demonstrates this)
- Widget rendering commands (unknown — may render locally or send pixel data)
- Firmware version queries
- Device identification

**Current state of knowledge:**
- Corsair's USB Vendor ID is `0x1B1C` (6940 decimal)
- The Xeneon Edge exposes **two separate USB devices**:
  1. **Main device**: Vendor "CORSAIR", Product "XENEON EDGE", Serial "145225445656" — this is the HID control channel for device settings (colour, brightness via proprietary protocol)
  2. **TouchScreen device**: Product ID `0x0859` (2137 decimal), Product "TouchScreen" — this is the touch digitiser, presented as a child device at a separate USB address
- The TouchScreen device is `bDeviceClass = 0` (defined at interface level), low-speed USB (`Device Speed = 1`), with `bcdDevice = 336` and a single configuration
- No public reverse engineering of the Xeneon Edge's HID protocol exists
- The user's gist demonstrates colour balance control, suggesting the HID protocol is at least partially understood
- **DDC/CI is confirmed working** on macOS — MonitorControl detects the Xeneon Edge with "Hardware (DDC)" control method, Display Identifier 2

**What the gist tells us:**
Based on the gist description ("Script to set an optimal color profile and balance on a Corsair Xeneon Edge touchscreen display on macOS without using iCue"), this confirms:
- USB HID communication with the Xeneon Edge is possible on macOS
- Colour profile/balance settings can be sent via USB HID
- This works without iCUE, so it's direct HID communication (likely using `hidapi` or IOKit HID Manager)

**Reverse engineering plan:**
1. **Identify the device**: Connect the Xeneon Edge to macOS and use `ioreg` or System Information to find the USB Product ID and interface list
2. **Capture on Windows**: When access to a Windows machine is available, use Wireshark with USBPcap to capture HID traffic between iCUE and the device while adjusting various settings
3. **Map the protocol**: Document each HID report (report ID, field offsets, value ranges) for each setting
4. **Implement on macOS**: Use IOKit HID Manager to send the same reports from macOS

**IOKit HID Manager approach (preferred for macOS native):**

```swift
import IOKit.hid

class XenonEdgeHIDController {
    private var manager: IOHIDManager?
    private var device: IOHIDDevice?

    // Corsair Vendor ID
    private let vendorID: Int = 0x1B1C
    // Xeneon Edge TouchScreen Product ID (discovered via ioreg)
    private let touchProductID: Int = 0x0859
    // Xeneon Edge main device Product ID — needs `ioreg` with wider grep to confirm
    private let mainProductID: Int = 0x0000 // TODO: run ioreg -p IOUSB -l for full XENEON EDGE entry

    func connect() throws {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        guard let manager else { throw HIDError.managerCreationFailed }

        let matchDict: [String: Any] = [
            kIOHIDVendorIDKey as String: vendorID,
            kIOHIDProductIDKey as String: productID
        ]

        IOHIDManagerSetDeviceMatching(manager, matchDict as CFDictionary)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else { throw HIDError.openFailed(result) }

        // Get matched devices
        guard let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
              let foundDevice = deviceSet.first else {
            throw HIDError.deviceNotFound
        }
        device = foundDevice
    }

    func sendReport(_ reportID: UInt8, data: [UInt8]) throws {
        guard let device else { throw HIDError.notConnected }
        var reportData = [reportID] + data
        let result = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(reportID), &reportData, reportData.count)
        guard result == kIOReturnSuccess else { throw HIDError.sendFailed(result) }
    }
}
```

## Device Discovery

To identify the Xeneon Edge among connected displays, we need to correlate the USB HID device with the display output. This is non-trivial on macOS.

**Strategy:**
1. Enumerate `NSScreen.screens` — find the screen with 2560×720 resolution
2. Use `CGDisplayIOServicePort` (deprecated but still functional) or `IODisplayConnect` to get the IOKit service for that display
3. Query the IOKit service for vendor/product IDs
4. Match against the USB HID device with the same Corsair vendor ID
5. Fall back to user selection if automatic matching fails

```swift
func findXenonEdge() -> NSScreen? {
    return NSScreen.screens.first { screen in
        let frame = screen.frame
        // Xeneon Edge is 2560×720
        return frame.width == 2560 && frame.height == 720
    }
}
```

## Priority Order for Controls

Different display settings may be controllable via different channels. Here's the priority:

| Setting | Primary Method | Fallback |
|---------|---------------|----------|
| Brightness | DDC/CI (VCP 0x10) | USB HID (if supported) |
| Contrast | DDC/CI (VCP 0x12) | USB HID (if supported) |
| Colour Temperature | USB HID (Corsair-specific) | DDC/CI (VCP 0x14) |
| Colour Balance (R/G/B gain) | USB HID (Corsair-specific) | DDC/CI (VCP 0x16/18/1A) |
| Input Source | DDC/CI (VCP 0x60) | Not available |
| Power State | DDC/CI (VCP 0xD6) | Not available |

## Security & Permissions

### USB HID Access on macOS

macOS restricts access to HID devices. The app will need:

1. **Input Monitoring permission** (System Settings > Privacy & Security > Input Monitoring) — required for accessing HID devices
2. **Possibly "Full Disk Access"** — depending on the specific IOKit path used
3. **No sandbox** — sandboxed apps cannot access arbitrary HID devices; this is why Ledge will distribute outside the App Store initially. The App Sandbox must also be disabled for the `CGEventTap` used by `TouchRemapper`
4. **Accessibility permission** (System Settings > Privacy & Security > Accessibility) — required for the `CGEventTap` used by `TouchRemapper` to remap touchscreen coordinates to the Xeneon Edge

### Entitlements

The app's entitlements should include:
```xml
<key>com.apple.security.device.usb</key>
<true/>
```

If distributing via Developer ID (notarised), these entitlements are permitted outside the sandbox.

## Discovered Device Information

From `ioreg -p IOUSB -l` on macOS:

```
Main device:
  USB Vendor Name = "CORSAIR"
  kUSBProductString = "XENEON EDGE"
  USB Serial Number = "145225445656"
  idVendor = 6940 (0x1B1C)
  Device Speed = 1

Child device:
  USB Product Name = "TouchScreen"
  idProduct = 2137 (0x0859)
  bDeviceClass = 0
  bcdDevice = 336
  bMaxPacketSize0 = 64
  bNumConfigurations = 1
  USBSpeed = 1
```

MonitorControl confirms: DDC hardware control works, display identified as "XENEON EDGE", Identifier 2.

## Next Steps

1. **~~Connect the Xeneon Edge to a Mac~~** — DONE. Device IDs discovered (see above). Still need the main XENEON EDGE `idProduct` — run `ioreg -p IOUSB -l` without grep to find the full entry for the parent CORSAIR device.

2. **~~Test DDC/CI~~** — DONE. MonitorControl confirms Hardware (DDC) works with the Xeneon Edge.

3. **Capture USB HID on Windows**: Use Wireshark + USBPcap while adjusting settings in iCUE. Focus on brightness, colour balance, and any widget-related communication.

4. **Integrate the gist**: Adapt the colour control code from the existing gist into the Ledge architecture.
