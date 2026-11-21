// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import VelaTheme

// Surfaces of the main window, drawn in a theme color or, when the theme's
// `vibrancy` puts them on a macOS material, the material tinted by that
// color. The rules live in `ThemeVibrancy` (VelaTheme) so the contrast
// checks and the previews agree with what's drawn here.

extension EnvironmentValues {
    /// The theme's vibrancy as drawn: `none` while Reduce Transparency is on.
    var effectiveVibrancy: ThemeVibrancy {
        theme.vibrancy.effective(reduceTransparency: accessibilityReduceTransparency)
    }
}

/// Fills a surface of the main window: the token's color, or with vibrancy
/// on, the surface's material with the color as a tint (see
/// `ThemeVibrancy.tint(_:)`).
struct SurfaceFill: View {
    @Environment(\.theme) private var theme
    @Environment(\.effectiveVibrancy) private var vibrancy
    let key: String
    let surface: ThemeSurface
    /// Floats over the window's own content (the hover-expanded sidebar),
    /// so its material blurs that content rather than the desktop.
    var isFloating = false

    init(_ key: String, on surface: ThemeSurface, isFloating: Bool = false) {
        self.key = key
        self.surface = surface
        self.isFloating = isFloating
    }

    var body: some View {
        // Every surface fill, tagged once here for Vela Dev's inspector.
        fill.devTag("Surface", tokens: [key])
    }

    @ViewBuilder
    private var fill: some View {
        let color = theme.surfaceColor(key, on: surface, vibrancy: vibrancy).color
        switch vibrancy.material(for: surface) {
        case .sidebar:
            VisualEffectBackground(material: .sidebar, blending: isFloating ? .withinWindow : .behindWindow)
                .overlay(color)
        case .window:
            // The window's own material, behind everything, shows through.
            color
        case nil:
            color
        }
    }
}

extension View {
    /// Fills the background with a main-window surface; see `SurfaceFill`.
    func surfaceBackground(_ key: String, on surface: ThemeSurface, isFloating: Bool = false) -> some View {
        background(SurfaceFill(key, on: surface, isFloating: isFloating))
    }
}

/// The main window's backdrop: `window.background`, or with `"window"`
/// vibrancy the window material (untinted: each surface above it brings its
/// own tint).
struct WindowBackdrop: View {
    @Environment(\.theme) private var theme
    @Environment(\.effectiveVibrancy) private var vibrancy

    var body: some View {
        backdrop.devTag("Window", tokens: [ThemeKey.windowBackground, ThemeKey.windowBorder])
    }

    @ViewBuilder
    private var backdrop: some View {
        if vibrancy.material(for: .content) == .window {
            VisualEffectBackground(material: .underWindowBackground, blending: .behindWindow)
        } else {
            theme[ThemeKey.windowBackground]
        }
    }
}

/// An `NSVisualEffectView` that follows the window's active state, like the
/// system's own sidebars, and lets clicks and drags through to SwiftUI.
struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    final class PassthroughEffectView: NSVisualEffectView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    func makeNSView(context: Context) -> PassthroughEffectView {
        let view = PassthroughEffectView()
        view.state = .followsWindowActiveState
        view.isEmphasized = false
        view.material = material
        view.blendingMode = blending
        view.setAccessibilityElement(false)
        return view
    }

    func updateNSView(_ view: PassthroughEffectView, context: Context) {
        if view.material != material { view.material = material }
        if view.blendingMode != blending { view.blendingMode = blending }
    }
}

extension View {
    /// Draws `window.border` as a 1-point outline just inside the window's
    /// edge, following its rounded corners. Apply at a window's root.
    func themedWindowBorder() -> some View {
        modifier(ThemedWindowBorder())
    }
}

private struct ThemedWindowBorder: ViewModifier {
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content.overlay {
            // Half of a 2-point stroke centered on the window's edge shows.
            ConcentricRectangle()
                .stroke(theme[ThemeKey.windowBorder], lineWidth: 2)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
