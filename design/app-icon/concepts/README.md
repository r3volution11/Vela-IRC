# Vela app icon: concepts

Proposals for replacing "Horizon Sail" with a truly minimal mark: one geometric **V** on a smooth navy background with a soft glow, in the style of the REV wordmark (chamfered corners, a dark ground, a glowing gradient). The colours are the current icon's palette, not REV's.

> **Decision (November 2026): E, Glint, is Vela's icon.** It's installed as `Vela/AppIcon.icon`, and its five other colourways are the Dock icons in Settings → Appearance. [`design/app-icon/README.md`](../README.md) documents the installed icon and how to rebuild it. The rest of this folder is the exploration as it was proposed.

Per-concept renders (1024 px, 16/32/64 px, appearances) aren't committed; run `src/build.sh` to regenerate them. **Start with [`contact-sheet.webp`](contact-sheet.webp)** (every concept at 512 px and at its real 32 px and 16 px sizes, on a light and a dark desktop). Then see **[`alternates-sheet.webp`](alternates-sheet.webp)** (colourways for the two finalists, A and D, and for E).

| | Concept | Idea | Small-size read |
|---|---|---|---|
| **A** | [Chamfer](A-chamfer/) | A bold V with 45° cuts on the outer top corners and a flat, cut foot. The purest form of the REV style. | Excellent |
| **B** | [Facet](B-facet/) | A solid V chiselled into four flat facets lit from the upper left, like a cut gem. | Good, a little busy at 16 px |
| **C** | [Twin Bars](C-bars/) | Two chamfered bars with ends cut square to the bar, split by a thin seam. A deep "mast" bar and a bright "sail" bar, echoing the old two sails. | Fair: lopsided at 16 px |
| **D** | [Leeward](D-sail/) | A's left arm, plus a right arm that is a wind-filled band ending in a slightly raised "flying" corner. The notch becomes a sail-shaped pocket of negative space. | Excellent |
| **E** | [Glint](E-glint/) | A pointed V cradling one small four-point star in its notch, a nod to the constellation. The star is its own layer. | Good; the star becomes a dot |
| **F** | [Neon](F-neon/) | A monoline V like a neon tube: pale core, tight halo, wide glow. Lighter and quieter than the others. | Good, thanks to its brightness; thinnest stroke |

Each concept folder contains:
- `X.svg`: the flat, self-contained SVG source on the macOS icon shape.
- `X.icon`: an **Icon Composer document** you can open and tweak.
- `X-1024.png`: the Liquid Glass render on the macOS grid.
- `X-16.png`, `X-32.png`, `X-64.png`: real-size renders.
- `X-legibility.png`: the real-size renders magnified 6×.
- `X-appearances.png`: Default, Dark, Clear and Tinted.

## Recommendation

*Doug chose E, Glint (see the decision above). The recommendation as it was made:*

**D Leeward is my pick, with A Chamfer as the safe alternative.** These two are the finalists with alternates.

- **D:**
  - It's as minimal and as legible at 16 px as A.
  - It keeps the one idea worth keeping from Horizon Sail: *vela* means "the sails". The sail cue lives in the silhouette and the negative space, not in a scene.
  - A plain V is common (Vivaldi, Venmo, Vue…). D's swept right arm makes it Vela's own.
  - It still carries the REV signature: the 45° chamfer on the left terminal and the cut foot.
  - The risk is that, at a glance, the asymmetry can suggest a check mark. I lowered the flying corner to 16 pt above the top line to keep it a V.
- **A** is the most faithful translation of REV and the most timeless. If D's asymmetry doesn't land, choose A.
- **E's star** works well as an *alternate* rather than the main icon. It could be an accent layer added to either finalist.
- **B** is handsome at large sizes but has more detail than the brief wants. **C** and **F** are weaker at 16 px.

## How the concepts are built

Coordinates are on the **1024-pt icon body**, which is Icon Composer's canvas, with y growing downward. On the macOS grid that body is drawn 824 px wide in a 1024 px canvas (100 px margins), with a soft drop shadow. That's how the `-1024.png` files and the contact sheet show it. The macOS 26 shape in the SVGs was measured from ictool's own mask: a continuous-corner rounded rect whose corner curve runs about 330 pt along each edge.

- **Size:** every V is drawn from a nominal 600–664 pt frame. After the chamfers cut the corners, each is 530–590 pt wide (52–58% of the body) and 520–560 pt tall. The table gives the visible box.
- **Optical centre:** each V is centred a few points below the true middle, because a V carries its weight at the top.
- **Strokes:** given perpendicular to the edge. The horizontal width is stroke ÷ cos(angle).
- **Angles:** measured from vertical.

| | Box (x, y) | Stroke | Arm angle | Chamfer | Other |
|---|---|---|---|---|---|
| A | 234–790, 250–790 | 150 (166 horizontal) | 25.7° | 74 pt along the top edge, cut at 45°; outer top corners only | Foot cut flat, 84 pt; notch apex at y 532 |
| B | 230–794, 246–806 | 156 | 28.3° | 58 pt at 45° | Pointed foot; the stroke-centre ridges meet on the axis at y 642; notch at y 477 |
| C | 248–776, 246–797 | 150 per bar | 30.4° | 46 pt on each leg of the bar's square outer corner | Bar ends square to the bar (the outer corner sits 76 pt below the inner one); 18 pt vertical seam; notch at y 516 |
| D | 222–810, 234–790 | 150 | 25.7° (left arm) | 74 pt at 45°, left terminal only | Right arm: outer edge (leech) a quadratic with a 30 pt sag; the inner edge is its true 150 pt offset, so the band keeps an even width; flying corner 16 pt above the top line; shifted 12 pt left to balance; notch at y 561 |
| E | 233–791, 262–787 (star up to 226) | 140 | 28.7° | 54 pt at 45° | Tip trimmed 22 pt up each edge so it stays crisp; star: four points with concave sides, 56 × 66 pt half-size, centred at y 292, own layer |
| F | 224–800, 262–780 | 96 | 27.8° | 36 pt at 45° | Foot 54 pt; no Liquid Glass on the V |

**Glow** (all concepts, in one non-glass layer):
- A radial bloom centred at (512, 600) with a 560 pt radius, plus a copy of the V's silhouette blurred with a 40 pt σ, at 55%.
- F adds a tight 11 pt halo.
- Liquid Glass is never applied to the glow. Glass outlines the alpha of any soft shape, which turns a glow into a visible disc.

## Palette

**Default** ("Vela"), taken from the current icon:

| Role | Hex | Where it comes from |
|---|---|---|
| Background, top → bottom | `#03050D` → `#09122B` | `icon.json` fill (Display P3), unchanged |
| Background, Dark | `#020309` → `#070E23` | `icon.json` dark fill, unchanged |
| V gradient, point → top | `#B4FAF4` → `#66E6EE` → `#34C6E6` → `#2296DA` | The right sail's stops, ending in the left arm's top blue |
| Deep facet (B only) | `#1A6FB8` | One step deeper than `#2296DA` |
| Glow | `#34C6E6` | Sail mid-tone |
| Bloom | `#1D5A9A` | Between the old haze blue and planet teal |
| Star (E) | `#FFFFFF` → `#DBFFFF` | The old horizon rim's core |
| Clear/Tinted V | `#FFFFFF` → `#D4DAE1` | Like the current `-mono` sails |

The gradient is bright at the V's point and deepens toward the arms, as if lit from below. It's a quiet echo of the old sunrise at the point.

**Alternates** (`alternates/<concept>/`: A, D and E). The V's ramp runs from its lightest to its deepest colour. The star column applies to E only:

| Colourway | Background | V ramp | Glow | Star (E) |
|---|---|---|---|---|
| Vela (default) | `#03050D` → `#09122B` | `#B4FAF4` `#66E6EE` `#34C6E6` `#2296DA` | `#34C6E6` | `#FFFFFF` → `#DBFFFF` |
| Midnight | `#010208` → `#060B1E` | `#F2FFFD` `#DBFFFF` `#9EFAFF` `#5FB8E8` | `#9EFAFF`, faint | `#FFFFFF` → `#DBFFFF` |
| Sunrise | `#070A1C` → `#1B1438` | `#FFF1C9` `#FFC98A` `#FF9A6B` `#F2667A` | `#FF9A6B` | `#FFF6DC` → `#FFC98A` (warm, like the V's point) |
| Graphite | `#16181C` → `#2A2D33` | `#FFFFFF` `#ECEFF3` `#C9D0D8` `#9AA4B0` | `#DCE2E8`, faint | `#FFFFFF` → `#ECEFF3` |
| Paper | `#FBFCFE` → `#E2E9F2` | `#34C6E6` `#2296DA` `#1A6FB8` `#0A3E7A` (light at the point, deep at the top) | `#34C6E6`, faint | `#1A6FB8` → `#0A3E7A` (deep, like the V's top) |
| Vivid | `#2AB4EA` → `#1E50D6` | `#FFFFFF` → `#D2F4FA` | `#0A1E5C` (a shadow-glow) | `#FFFFFF` |

On E, the star is checked in every colourway. White works on the four dark grounds and on Vivid. On Sunrise, a white star looked cold beside the peach V, so it takes the V's warm point colours. On Paper, the original mid-blue star looked washed out next to the deep V, so it takes the V's deep top colours instead.

Sunrise's warm ramp is the only one that isn't taken from the current icon. It's tuned to sit on the same deep navy, and it reads as the old icon's sunrise.

## Icon Composer layers and the macOS 26 appearances

Each `.icon` is built so that the V is a separable foreground. That's what the system needs to derive the Dark, Clear and Tinted appearances:

| Icon Composer element | Content | Default | Dark | Clear | Tinted |
|---|---|---|---|---|---|
| Document fill (`fill-specializations`) | Linear navy gradient, top → 78% | Navy | The darker `dark` fill | Replaced by the system's glass | Replaced by the tint |
| Back group, layer `glow` (`glow.svg`, glass off) | Bloom + blurred V | Shown | Opacity 0.85 | Not visible | Hidden (`hidden-specializations`) |
| Front group, layer `v` (`v.svg`, Liquid Glass on). C has `bar-right` and `bar-left` | The V | Gradient V with a specular rim and a layer-colour shadow (opacity 0.5); translucency off so the colour stays rich | Same | White glass V | `v-mono.svg` (white → light grey), tinted by the system |
| Front group, layer `accent` (E only) | The star | White star | Same | Glass | `accent-mono.svg` |

`*-appearances.png` shows all six renditions for each concept, rendered by `ictool`.

**Construction notes for whoever installs the winner:**
- **The V is one flat shape**, so the system's glass, Clear and Tinted treatments always have a clean silhouette to work with.
- **B's facets collapse** into a single shape in `v-mono.svg`.
- **F** turns glass off on its V, because glass rims dull a neon tube.
- **SVG filters:** CoreSVG (used by Icon Composer, ictool and NSImage) applies an SVG `filter` on a `<path>` but ignores one on a `<g>`. Keep blurs on paths.

**To install a concept** (done for E):
1. Write its `.icon` over `Vela/AppIcon.icon`: `python3 -I src/concepts.py --icon <letter> vela Vela/AppIcon.icon`. For E, `design/app-icon/build.sh` does this and also writes the Dock icons.
2. Run `scripts/export-icon.sh` to regenerate the README icon, favicons, `logo.png`, `apple-touch-icon.png` and `vela-icon.webp`.
3. Run `website/scripts/screenshots.sh … og-image` to refresh the social card.

The 16 px favicon is the size where A and D clearly beat the others.

## Alternate icons on macOS: what we can promise

**Short version:**
- macOS has no alternate-app-icon API.
- A sandboxed, notarized app can choose its icon only in the **Dock (and the app switcher) while it's running**.
- Everywhere else, the bundle's icon shows, and that's the one that follows the user's macOS 26 icon style.
- Bear, which is sandboxed, works exactly this way.

### What `NSApplication.applicationIconImage` changes

- **It's temporary, and only for the Dock tile.** "Assign an image to this property when you want to temporarily change the app icon in the dock app tile… To restore your app's original icon, set this property to `nil`." It doesn't persist after quit. ([NSApplication.applicationIconImage](https://developer.apple.com/documentation/appkit/nsapplication/applicationiconimage))
- **The Dock tile uses it by default.** "An application Dock tile defaults to display the application's `applicationIconImage`." ([NSDockTile](https://developer.apple.com/documentation/appkit/nsdocktile))
- **Cmd-Tab also follows it (not documented).**
- **Finder, Spotlight, Launchpad/Apps and notification banners keep the bundle icon.**
- **Alerts and the About panel:** set their icons explicitly (`NSAlert.icon`, `.applicationIcon` in the About panel options) rather than relying on them following the runtime image.
- **The image is drawn as-is**, a flat bitmap.
  - It needs the icon shape and margins baked in. The `*-1024.png` files here are already in that format.
  - **It doesn't follow** the user's Dark, Clear or Tinted icon style. Setting it back to `nil` restores the compiled `.icon` with full system styling.

### Can the app change its bundle icon at runtime?

**No for Vela.** `NSWorkspace.setIcon(_:forFile:options:)` is the wrong tool for Vela:

- **What it writes:** it sets the folder's custom-icon flag and stores the image in an invisible `Icon\r` file at the bundle root. ([DTS, thread 812425](https://developer.apple.com/forums/thread/812425); [thread 120992](https://developer.apple.com/forums/thread/120992))
- **The sandbox blocks it.** "The sandbox will always allow an app… read-only access to its own bundle." ([DTS, thread 652379](https://developer.apple.com/forums/thread/652379)) `setIcon` also requires that the file "must exist and be writable by the user." ([setIcon](https://developer.apple.com/documentation/appkit/nsworkspace/seticon(_:forfile:options:)))
- **Code signature:**
  - Apple DTS says a custom icon "doesn't affect the app's code signature" (thread 812425), because the `Icon\r` file sits outside the seal.
  - But Apple's guidance is still "Bundles should be treated as read-only once they have been signed" ([TN2206](https://developer.apple.com/library/archive/technotes/tn2206/_index.html)). Also: "modifying your app's bundle isn't supported because it breaks the seal" ([Embedding nonstandard code structures](https://developer.apple.com/documentation/xcode/embedding-nonstandard-code-structures-in-a-bundle)).
  - Code signing rejects Finder-info and resource-fork extended attributes inside a bundle ([QA1940](https://developer.apple.com/library/archive/qa/qa1940/_index.html)).
  - On this Mac, apps carrying `Icon\r` pass plain `codesign --verify` and `spctl --assess` ("accepted, Notarized Developer ID"). They **fail** `codesign --verify --strict` with "Disallowed xattr com.apple.FinderInfo".
- **Notarization:** since macOS 13, Gatekeeper re-checks notarized apps and blocks one that is "no longer validly signed" ([WWDC22 session 10096](https://developer.apple.com/videos/play/wwdc2022/10096/)). An `Icon\r` file hasn't triggered that in practice, but it's outside what Apple supports.
- **Updates:** every Sparkle update or DMG reinstall replaces the bundle, so the custom icon would be lost each time.
- **Bear's team on this:** "the sandbox prevents us from permanently changing the app icon." ([Bear community](https://community.bear.app/t/app-icon-changes-from-default-red-to-customized-only-when-i-opened-the-application/14963))

### What macOS 26 offers natively

- **Icon & widget style:** **System Settings › Appearance › Icon & widget style** offers Default, Dark, Clear (light, dark or automatic) and Tinted. It's chosen by the user, system-wide, for every app; there's no per-app control. ([Apple Support](https://support.apple.com/guide/mac-help/change-appearance-settings-mchlp1225/mac))
  - The concepts' layer structure is built for this, so Vela's real icon will look right in all four.
- **No alternate-icon API on macOS.**
  - The HIG lists alternate app icons only for "iOS, iPadOS, tvOS, and compatible apps running in visionOS". ([HIG: App icons](https://developer.apple.com/design/human-interface-guidelines/app-icons))
  - `UIApplication.setAlternateIconName` and `supportsAlternateIcons` are UIKit (iOS and Mac Catalyst), not AppKit. ([supportsAlternateIcons](https://developer.apple.com/documentation/uikit/uiapplication/supportsalternateicons))
  - A Catalyst developer reported "feature is not supported" on the Mac. ([forum thread 721930](https://developer.apple.com/forums/thread/721930))
  - The `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` and "Include All App Icon Assets" build settings only put extra icons into `Assets.car`. Nothing on macOS switches to them. ([Build settings reference](https://developer.apple.com/documentation/xcode/build-settings-reference); [Configuring alternate app icons](https://developer.apple.com/documentation/xcode/configuring-your-app-to-use-alternate-app-icons))
  - The macOS 27.2 SDK on this Mac adds nothing new, and there's no public API to read the user's icon style.
- **Dock tile plug-ins** (`NSDockTilePlugIn`) can draw the Dock tile while the app is quit ([NSDockTilePlugIn](https://developer.apple.com/documentation/appkit/nsdocktileplugin)), but:
  - Apple DTS calls them "an old loadable plugin API… not allowed in App Store apps and… not something I'd recommend creating today". ([thread 762250](https://developer.apple.com/forums/thread/762250))
  - For a sandboxed app, the plug-in can't see the app's container preferences without a temporary-exception entitlement. ([thread 770315](https://developer.apple.com/forums/thread/770315))

### Recommended approach

1. **Ship an in-app icon picker that sets `NSApp.applicationIconImage` at launch**, the way Bear does.
   - Ship each alternate as a pre-rendered macOS-grid image, like the `*-1024.png` renders here.
   - For "Default", set `nil`, so the real `.icon` keeps its Dark, Clear and Tinted styling.
   - Optionally, use an alternate's ictool *Dark* render when the app's appearance is dark.
2. **Don't write `Icon\r` or call `setIcon` on the bundle.**
3. **Consider a Dock tile plug-in only for the Developer ID build, and only if users ask** for the icon to persist while Vela is quit. It's deprecated in spirit, banned on the App Store, and needs a sandbox exception.

**What we can promise Doug's users:** "Pick the icon Vela shows in the Dock and app switcher while it's running. When Vela is quit, and in Finder, Spotlight and the Apps list, macOS shows Vela's standard icon, which follows your Icon & widget style. Alternate icons are fixed images and don't change with Dark, Clear or Tinted."

## Rebuilding

**To rebuild everything:**

```sh
design/app-icon/concepts/src/build.sh                 # all concepts + sheets (alternates for A, D and E)
FINALISTS=AD design/app-icon/concepts/src/build.sh    # alternates for other concepts
python3 -I design/app-icon/concepts/src/concepts.py --icon E sunrise out.icon   # one .icon
```

**What the build runs:**
- `src/concepts.py` holds the geometry and palettes. It writes the `.icon` documents and the flat SVGs.
- `ictool` renders them.
- `src/compose.swift` lays out the PNGs and sheets.

**Output format:** the PNGs are Display P3, quantised to 8 bits with a light dither so the dark gradients don't band. They need Xcode 26 or later (ictool), and the build writes only inside this folder.
