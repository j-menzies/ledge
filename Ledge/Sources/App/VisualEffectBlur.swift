import SwiftUI
import AppKit

/// SwiftUI wrapper around `NSVisualEffectView` for macOS vibrancy and blur effects.
///
/// When placed as a widget background, this blurs whatever is behind the widget
/// (desktop wallpaper, background image, or other content) to create a frosted-glass look.
///
/// Usage:
/// ```swift
/// VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
///     .clipShape(RoundedRectangle(cornerRadius: 12))
/// ```
struct VisualEffectBlur: NSViewRepresentable {

    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    let state: NSVisualEffectView.State

    init(
        material: NSVisualEffectView.Material = .hudWindow,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
        state: NSVisualEffectView.State = .active
    ) {
        self.material = material
        self.blendingMode = blendingMode
        self.state = state
    }

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}
