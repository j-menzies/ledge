# Ledge

A native macOS widget dashboard for the Corsair Xeneon Edge touchscreen display.

Fills the gap left by Corsair's Windows-only iCUE software — providing a configurable, touch-friendly widget system that runs on the Xeneon Edge without stealing focus from your active application.

## Status

Early design phase. See the [docs/](./docs/) directory for the project design.

## Documentation

- **[Overview](docs/OVERVIEW.md)** — Project goals, research findings, and context
- **[Architecture](docs/ARCHITECTURE.md)** — System design, component breakdown, technology choices
- **[Widget System](docs/WIDGET_SYSTEM.md)** — Plugin architecture, widget protocol, built-in widget catalogue
- **[USB Protocol](docs/USB_PROTOCOL.md)** — DDC/CI and USB HID control approaches
- **[Focus Management](docs/FOCUS_MANAGEMENT.md)** — How touch interaction works without stealing focus
- **[Roadmap](docs/ROADMAP.md)** — Phased development plan

## Key Idea

macOS `NSPanel` with `.nonactivatingPanel` style mask allows the widget dashboard to receive touch input on the Xeneon Edge without activating the application or stealing focus from your foreground app. This is the same mechanism used by Spotlight and Alfred.

## Related

- [Colour control gist](https://gist.github.com/rliessum/288604c6899e898957dc5d504ce76a48) — Basic USB colour profile control for the Xeneon Edge on macOS
- [MonitorControl](https://github.com/MonitorControl/MonitorControl) — DDC/CI brightness control for macOS (reference implementation)
- [OpenLinkHub](https://github.com/jurkovic-nikola/OpenLinkHub) — Open source Corsair device control for Linux
