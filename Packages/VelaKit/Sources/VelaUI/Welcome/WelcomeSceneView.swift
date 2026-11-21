// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Savage
import SwiftUI

/// The welcome scene in a Canvas. It's still: it draws when it first shows,
/// when its size changes and when its colors do, and at no other time (it
/// reads nothing but `scene`, and `==` lets SwiftUI skip it otherwise).
/// Decorative, so hidden from VoiceOver.
struct WelcomeSceneView: View, Equatable {
    let scene: WelcomeScene

    #if DEBUG
    /// How many times a welcome scene has been drawn, for tests.
    static var drawCount = 0
    #endif

    var body: some View {
        Canvas { context, size in
            #if DEBUG
            Self.drawCount += 1
            #endif
            var painter = CanvasPainter(context: context)
            scene.draw(&painter, size: size)
        }
        .accessibilityHidden(true)
    }

    nonisolated static func == (a: WelcomeSceneView, b: WelcomeSceneView) -> Bool {
        a.scene == b.scene
    }
}

/// Sizes for the welcome screen.
enum WelcomeLayout {
    /// The scene's width range. Below the minimum it's left out.
    static let minSceneWidth: CGFloat = 320
    static let maxSceneWidth: CGFloat = 720
    static let horizontalMargin: CGFloat = 32
    static let verticalMargin: CGFloat = 24

    /// The scene's size in a pane of `available` points, or `nil` when it
    /// doesn't fit. `textHeight` is what the words and button below it need.
    /// (The title rises over the scene by about as much as its own height,
    /// so its size doesn't count.)
    static func sceneSize(in available: CGSize, textHeight: CGFloat) -> CGSize? {
        let byWidth = available.width - 2 * horizontalMargin
        let byHeight = (available.height - 2 * verticalMargin - textHeight) * WelcomeScene.aspectRatio
        let width = min(maxSceneWidth, byWidth, byHeight).rounded(.down)
        guard width >= minSceneWidth else { return nil }
        return CGSize(width: width, height: (width / WelcomeScene.aspectRatio).rounded())
    }

    /// The title's point size: in proportion to the scene, never smaller
    /// than the old 22 pt title.
    static func titleSize(sceneWidth: CGFloat?) -> CGFloat {
        max(22, ((sceneWidth ?? 0) / 15).rounded())
    }

    /// How far the title rises over the bottom of the scene.
    static func titleLift(sceneHeight: CGFloat?) -> CGFloat {
        ((sceneHeight ?? 0) * 0.13).rounded()
    }
}
