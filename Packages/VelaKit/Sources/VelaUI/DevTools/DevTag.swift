// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI

// Tagging for Vela Dev's developer tools (Developer menu, Debug builds only).
//
// `.devTag(_:tokens:font:padding:)` names a view and the theme tokens it's
// drawn with, so Inspect Element (⌥⌘I) can say what's under the pointer and
// Layout Outlines can draw its box. In Debug builds a tagged view carries a
// background that's empty until one of those tools is on; then it reports
// its frame to its window's `DevTagRegistry`. In Release builds
// `devTag` returns the view itself and never evaluates its arguments: no
// modifier, no stored properties, no environment reads.

#if DEBUG

/// What a tagged view tells the developer tools about itself.
struct DevTag: Equatable {
    /// What the view is ("Message row", "Sidebar row").
    var name: String
    /// The theme tokens it draws with, most telling first.
    var tokens: [String]
    /// The font its text uses, when the tag knows it better than the
    /// environment does (fonts set on the text inside the view).
    var font: Font?
    /// The padding between its frame and its content, when known.
    var padding: EdgeInsets?
}

extension View {
    /// Tags this view for Vela Dev's Inspect Element and Layout Outlines.
    /// Put it after the view's padding and frame, so the tag's frame is the
    /// view's box. Compiled out of release builds, arguments and all.
    func devTag(_ name: String, tokens: [String] = [], font: Font? = nil, padding: EdgeInsets? = nil) -> some View {
        modifier(DevTagModifier(tag: DevTag(name: name, tokens: tokens, font: font, padding: padding)))
    }
}

/// Adds the probe only while a tool that needs tags is on. The background is
/// always there, empty when the tools are off, so turning them on never
/// changes the tagged view's identity (or resets its state).
struct DevTagModifier: ViewModifier {
    let tag: DevTag

    func body(content: Content) -> some View {
        content.background {
            if DevTools.shared.isTagging {
                DevTagProbe(tag: tag)
            }
        }
    }
}

/// Reports a tagged view's frame (and the part of it its scroll view shows)
/// to the window's registry, in window (global) coordinates.
struct DevTagProbe: View {
    let tag: DevTag
    @Environment(\.devTagRegistry) private var registry
    @Environment(\.font) private var inheritedFont
    @Environment(\.fontResolutionContext) private var fontContext
    @State private var id = DevTagRegistry.makeID()

    var body: some View {
        Color.clear
            .onGeometryChange(for: DevTagGeometry.self, of: DevTagGeometry.init) { geometry in
                registry?.update(id, geometry: geometry)
            }
            .onChange(of: tag, initial: true) { _, tag in
                registry?.update(id, tag: tag, font: tag.font ?? inheritedFont ?? .body, fontContext: fontContext)
            }
            .onDisappear { registry?.remove(id) }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Where a tagged view is: its frame, and the part of it inside its scroll
/// view (rows scrolled partly out of sight, or kept laid out just outside
/// it, are outlined only where they show).
nonisolated struct DevTagGeometry: Equatable, Sendable {
    var frame: CGRect
    var visibleFrame: CGRect

    init(frame: CGRect, visibleFrame: CGRect) {
        self.frame = frame
        self.visibleFrame = visibleFrame
    }

    /// Read in `onGeometryChange`'s transform, off the main actor.
    init(_ proxy: GeometryProxy) {
        let frame = proxy.frame(in: .global)
        self.frame = frame
        if let scroll = proxy.bounds(of: .scrollView) {
            // `bounds(of:)` is in this view's own coordinates.
            let local = proxy.frame(in: .local)
            let shown = local.intersection(scroll)
            visibleFrame = shown.isNull ? .null : shown.offsetBy(dx: frame.minX - local.minX, dy: frame.minY - local.minY)
        } else {
            visibleFrame = frame
        }
    }
}

extension EnvironmentValues {
    /// The window's tag registry (`DevToolsHost`); nil outside one.
    @Entry var devTagRegistry: DevTagRegistry?
}

#else

extension View {
    /// Release builds: the view itself. The arguments are autoclosures that
    /// are never called, so nothing a call site passes is evaluated.
    @inline(__always)
    func devTag(
        _ name: @autoclosure () -> String,
        tokens: @autoclosure () -> [String] = [],
        font: @autoclosure () -> Font? = nil,
        padding: @autoclosure () -> EdgeInsets? = nil
    ) -> Self {
        self
    }
}

#endif
