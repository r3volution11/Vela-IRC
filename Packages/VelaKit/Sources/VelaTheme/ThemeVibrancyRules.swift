// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// The kinds of surface in the main window, for deciding what a theme's
/// `vibrancy` puts on a material.
public enum ThemeSurface: Sendable, Hashable, CaseIterable {
    /// The sidebar tree and the collapsed rail (`sidebar.background`,
    /// `rail.background`).
    case sidebar
    /// The tab stacks: strips at the top or bottom (`tab.barBackground`,
    /// `tab.serverBackground`) and tabs in the title bar.
    case tabs
    /// The title strip, conversation, message bar and member list
    /// (`titleBar.background`, `chat.background`,
    /// `input.containerBackground`, `memberList.background`).
    case content
}

/// A macOS material a surface is drawn on.
public enum ThemeMaterial: Sendable, Hashable {
    /// The sidebar material, as in Finder's and Mail's sidebars.
    case sidebar
    /// The material behind a translucent window's content.
    case window
}

/// What `vibrancy` does, in one place so the app, the previews and the
/// contrast checks agree.
///
/// - `none`: nothing is on a material.
/// - `sidebar`: the sidebar, rail and tab stacks are on the sidebar material.
/// - `window`: the sidebar and rail are on the sidebar material, the rest of
///   the window on the window material.
///
/// A surface on a material is drawn in its theme color as a tint over it:
/// an opaque color at `tintOpacity`, a color with its own alpha exactly as
/// written (`#RRGGBB00` shows the bare material). With Reduce Transparency
/// on, every theme is drawn as with `none`. The Settings and Theme Editor
/// windows are always opaque.
extension ThemeVibrancy {
    /// How strongly an opaque theme color tints the material under it.
    public static let tintOpacity = 0.7

    /// The vibrancy actually drawn: `none` while Reduce Transparency is on.
    public func effective(reduceTransparency: Bool) -> ThemeVibrancy {
        reduceTransparency ? .none : self
    }

    /// The material a surface shows through its color, or `nil` if it's
    /// painted opaque.
    public func material(for surface: ThemeSurface) -> ThemeMaterial? {
        switch (self, surface) {
        case (.none, _): nil
        case (_, .sidebar): .sidebar
        case (.sidebar, .tabs): .sidebar
        case (.sidebar, .content): nil
        case (.window, .tabs), (.window, .content): .window
        }
    }

    /// Whether the window needs to let what's behind it through.
    public var isTranslucent: Bool { self != .none }

    /// A surface color as drawn over a material: opaque colors become a
    /// `tintOpacity` tint, translucent ones are used as written.
    public static func tint(_ color: ThemeColor) -> ThemeColor {
        color.alpha >= 1 ? color.withAlpha(tintOpacity) : color
    }

    /// The opacity at which `materialStandIn(for:)` models the material.
    public static let standInMaterialOpacity = 0.75

    /// A stand-in for a material in contrast checks, which can't know
    /// what's behind the window: the material, modeled as black (dark
    /// themes) or white (light themes) at `standInMaterialOpacity`, over the
    /// least favorable desktop: white behind a dark theme, black behind a
    /// light one.
    public static func materialStandIn(for kind: ThemeKind) -> ThemeColor {
        switch kind {
        case .dark: ThemeColor.black.withAlpha(standInMaterialOpacity).composited(over: .white)
        case .light: ThemeColor.white.withAlpha(standInMaterialOpacity).composited(over: .black)
        }
    }

    /// The tokens painted directly on a surface (the ones `tint(_:)`
    /// applies to), and which surface each is.
    public static let surfaceTokens: [String: ThemeSurface] = [
        ThemeKey.sidebarBackground: .sidebar,
        ThemeKey.railBackground: .sidebar,
        ThemeKey.tabBarBackground: .tabs,
        ThemeKey.tabServerBackground: .tabs,
        ThemeKey.titleBarBackground: .content,
        ThemeKey.chatBackground: .content,
        ThemeKey.inputContainerBackground: .content,
        ThemeKey.memberListBackground: .content,
    ]

    /// Full-width row colors drawn over a surface token, which are tinted
    /// the same way so they don't stand out as opaque bands, and the
    /// surface token they're drawn over.
    public static let rowTokens: [String: String] = [
        ThemeKey.chatHighlightBackground: ThemeKey.chatBackground,
        ThemeKey.chatSelfMessageBackground: ThemeKey.chatBackground,
    ]
}

extension ResolvedTheme {
    /// The color to paint a surface token with: as-is when its surface isn't
    /// on a material under `vibrancy` (pass the effective vibrancy, see
    /// `ThemeVibrancy.effective(reduceTransparency:)`), otherwise its tint.
    public func surfaceColor(_ key: String, on surface: ThemeSurface, vibrancy: ThemeVibrancy) -> ThemeColor {
        let color = color(key)
        return vibrancy.material(for: surface) == nil ? color : ThemeVibrancy.tint(color)
    }
}
