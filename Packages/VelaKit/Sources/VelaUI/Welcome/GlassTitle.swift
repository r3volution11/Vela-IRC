// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI

/// The welcome screen's title, glassy, in the theme's own text color: a
/// light-to-full gradient, a highlight across the top and a soft shadow.
/// It stays plain text to VoiceOver (a heading).
struct GlassTitle: View {
    let title: LocalizedStringKey
    let scene: WelcomeScene
    let font: Font
    /// The font's point size, for the shadows.
    let size: CGFloat

    var body: some View {
        let text = Text(title).font(font)
        let dark = scene.dark
        text
            .foregroundStyle(LinearGradient(colors: [scene.fg.mix(.white, dark ? 0.45 : 0.25).swiftUI, scene.fg.swiftUI, scene.fg.mix(scene.accent, 0.25).swiftUI],
                                            startPoint: .top, endPoint: .bottom))
            .overlay {
                // The highlight: strong on dark text backgrounds, gentle on
                // light ones, where it would wash the letters out.
                text.foregroundStyle(LinearGradient(stops: [.init(color: SceneRGB.white.c(dark ? 0.55 : 0.30).swiftUI, location: 0),
                                                            .init(color: SceneRGB.white.c(0).swiftUI, location: dark ? 0.45 : 0.32)],
                                                    startPoint: .top, endPoint: .bottom))
                    .blendMode(dark ? .plusLighter : .screen)
                    .accessibilityHidden(true)
            }
            .shadow(color: (dark ? SceneRGB.black : scene.fg).c(dark ? 0.55 : 0.22).swiftUI, radius: size * 0.22, y: size * 0.10)
            .shadow(color: scene.accent.c(0.25).swiftUI, radius: size * 0.5, y: 0)
            .multilineTextAlignment(.center)
            .accessibilityAddTraits(.isHeader)
    }
}
