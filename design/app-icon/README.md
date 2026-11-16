# Vela app icon: "Horizon Sail"

A glass V rises from the glowing cyan edge of a planet at sunrise, seen from orbit. Its point rests on the horizon where the sun is coming up, and a faint ray of light rises from there through the V's notch. The two arms are deliberately unequal, so the V also reads as a sail:

- **Left arm:** slim and taut, with straight, mast-like edges.
- **Right arm:** a broad sail. Its outer edge bellies out as if filled by solar wind, and its top edge is pulled slightly hollow, so it ends in a sharp, flying corner.

*Vela* is Latin for "the sails", and the name of a southern constellation.

## Files

- **[`Vela/AppIcon.icon`](../../Vela/AppIcon.icon)** is the icon itself, an Icon Composer document. Xcode compiles it directly into the app, with macOS 26 Liquid Glass and Default, Dark, Clear and Tinted appearances. Open it in Icon Composer (Xcode → Open Developer Tool → Icon Composer) to adjust glass, shadows or translucency.
- **`params.json`** holds the V's geometry. Both generators read it, so the sun and ray always stay under the V.
- **`gen/sails.py`** writes the four sail SVGs. The `-mono` versions are bright neutral sails used for the Clear and Tinted appearances.
- **`gen/space.swift`** renders the background: planet, atmosphere rim, sun, ray, faint nebula and stars. It writes `space.png` and a deeper `space-dark.png` for the Dark appearance. Its random stars use a fixed seed, so rebuilds are identical.
- **`build.sh`** regenerates all of the above and renders previews of every appearance.

## Changing the icon

1. Edit `params.json` (see the table below), or the colours in `gen/sails.py` (the `stops([...])` lists) and the palette constants at the top of `gen/space.swift`.
2. Run `design/app-icon/build.sh` and check the previews. They're Display P3, so view them in a colour-managed app such as Preview.
3. Run `scripts/export-icon.sh` to refresh the README icon and the website's favicons, logo and home-page icon.
4. To refresh the social card, run `website/scripts/screenshots.sh <path to Vela.app> og-image`.

| Knob | What it does |
|---|---|
| `shiftX` | Moves the whole V, sun and ray horizontally. This is the main optical-centering control. |
| `scale` | Scales the V about its point. At 1.035 the V is 72% of the canvas width. Keep the top-right corner clear of the rounded icon edge. |
| `point` | The V's point before `shiftX`. Its y should be about `limbTop - 2`, so the point rests on the horizon. |
| `limbTop`, `planetRadius` | The horizon's height and its curvature. |
| `notch` | Where the inner edges meet. A higher notch gives a sturdier V at 32 px. |
| `left.outerTop`, `left.innerTop` | The slim arm's angled top cut. The distance between them sets its width. |
| `right.head`, `right.headCtrl`, `right.clew` | The sail's top edge and its sharp flying corner. Moving `head` right widens the notch. |
| `right.belly1`, `right.belly2` | How full the sail's wind-filled outer edge is. |
| `fillet` | Corner rounding. |
| `seams` | The two faint seams on the big sail. |

Coordinates are on the 1024-point canvas, with y growing downward. Each build prints the V's size and balance.

## Palette

| Role | Colours |
|---|---|
| Sky | `#03050D` → `#09122B` (Dark: `#020309` → `#070E23`) |
| Right sail, point → top | `#B4FAF4` → `#66E6EE` → `#34C6E6` → `#24A8DE` |
| Left arm, point → top | `#A6F6F0` → `#4AD4E6` → `#22ACDC` → `#2296DA` |
| Planet rim and sun | rim `#38DBFF` with a `#DBFFFF` core; sun glow `#9EFAFF` |
| Planet | `#054C61` → `#02070C` |
