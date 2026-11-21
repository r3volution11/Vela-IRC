# Welcome scene

The picture on Vela's welcome screen: a river winding through a mountain valley, above **Welcome to Vela**. It shows until you add a network, and whenever no conversation is open (then it says **Pick a conversation**).

- **Dark themes get night:** a full moon with its seas and craters, Vela's eight stars among many fainter ones, and a stargazer at a telescope aimed at the moon.
- **Light themes get day:** the sun, clouds, birds, and a kayaker paddling upstream toward the sun.
- **The style:** a flat background with gradients for depth, and figures shaded like a 90s cartoon. No outlines.
- **The colors come from the theme:** the chat background, text and secondary text, and the accent. The figures have their own colors, lit by the moon or the sun. A custom theme, a new accent or `appearance.colorCustomizations` change the picture too.

## Where it lives

The drawing is code, in [`Packages/VelaKit/Sources/VelaUI/Welcome/`](../../Packages/VelaKit/Sources/VelaUI/Welcome):

- `WelcomeScene.swift`: the theme colors it uses, the palette made from them, and the valley.
- `WelcomeSky.swift`: the moon, the sun and the stars.
- `WelcomeStargazer.swift` and `WelcomeKayaker.swift`: the figures, and the lighting they share.
- `WelcomeGeometry.swift`: shapes and small math they share.
- `GlassTitle.swift`: the title, in the theme's text color with a highlight and a shadow.
- `WelcomeSceneView.swift`: the Canvas in the app, and how big it is. It's 320 to 720 points wide, and left out when even 320 doesn't fit. The welcome screen itself is `EmptyStateView`, in `Window/MainWindowView.swift`.
- `ScenePainter.swift`: what the drawing draws through. In the app that's a SwiftUI Canvas.
- `SVGPainter.swift`: the same drawing written as an SVG.

Its random parts (stars, rocks, ripples) come from a seeded generator, so a theme and a size always give the same picture.

## Exporting it

```sh
design/welcome-scene/export.sh          # into design/welcome-scene/exports
design/welcome-scene/export.sh <dir>    # into <dir>
```

It writes, from the app's code:

- `vela-welcome-night.png` and `.svg`, in Palenight.
- `vela-welcome-day.png` and `.svg`, in Lighter.
- `themes/vela-welcome-<night|day>-<theme>.png` and `.svg`, for every built-in theme.

Each is 1600 × 1013 points. The PNG is 2× (3200 × 2026 pixels). The edges fade to transparent, as in the app.

`exports/` isn't checked in. Run the script again after changing the drawing.

## The SVG

The SVG is all vectors: paths, gradients, clip paths and masks. Nothing in it is a picture. The moon's seas have a soft edge, an SVG blur (`feGaussianBlur`).

- **In Safari (WebKit),** it matches the app. Other browsers and design apps follow the same SVG rules.
- **In Preview, Quick Look and Finder,** the moon's seas have hard edges: macOS's own SVG renderer doesn't draw SVG filters.
- **Masked groups have an inner group at 99.99% opacity.** Apple's renderers mask each shape of a group on its own unless the group has an opacity, so without it overlapping shapes would show through at the faded edges.

The `Welcome scene SVG fidelity` test renders both and compares them.
