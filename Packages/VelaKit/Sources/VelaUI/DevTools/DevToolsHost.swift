// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

#if DEBUG

import SwiftUI
import VelaTheme

extension View {
    /// Vela Dev: the developer tools' layer over a window's content (every
    /// scene's root, from `velaEnvironment`). It holds the window's tag
    /// registry and draws the inspector, the outlines and, in the main
    /// window, the Performance HUD. With every tool off it draws nothing.
    /// `registry` is for tests; windows make their own.
    func devToolsHost(isPrimary: Bool, registry: DevTagRegistry? = nil) -> some View {
        modifier(DevToolsHost(isPrimary: isPrimary, injected: registry))
    }
}

struct DevToolsHost: ViewModifier {
    let isPrimary: Bool
    let injected: DevTagRegistry?
    @State private var own = DevTagRegistry()

    func body(content: Content) -> some View {
        let registry = injected ?? own
        let tools = DevTools.shared
        let showsHUD = isPrimary && tools.showsPerformanceHUD
        content
            .environment(\.devTagRegistry, registry)
            .overlay {
                if tools.isTagging || showsHUD {
                    DevToolsOverlay(registry: registry, showsHUD: showsHUD)
                }
            }
            .onChange(of: tools.isInspecting) { _, inspecting in
                if !inspecting { registry.clearInspection() }
            }
    }
}

/// Everything the tools draw over one window, in that window's coordinates.
struct DevToolsOverlay: View {
    let registry: DevTagRegistry
    let showsHUD: Bool

    var body: some View {
        let tools = DevTools.shared
        GeometryReader { proxy in
            let origin = proxy.frame(in: .global).origin
            ZStack(alignment: .topLeading) {
                if tools.showsOutlines {
                    DevOutlines(entries: registry.shownEntries, origin: origin)
                }
                if tools.isInspecting {
                    DevInspector(registry: registry, origin: origin, bounds: proxy.size)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .overlay(alignment: .topTrailing) {
                if showsHUD {
                    DevPerformanceHUD(monitor: tools.performance)
                        .padding(.top, 60)
                        .padding(.trailing, 12)
                }
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Inspect Element

struct DevInspector: View {
    let registry: DevTagRegistry
    /// The overlay's origin in window coordinates.
    let origin: CGPoint
    let bounds: CGSize
    @Environment(\.theme) private var theme
    @Environment(\.openWindow) private var openWindow
    @State private var panelSize = CGSize(width: 280, height: 160)

    var body: some View {
        let inspected = registry.inspected
        let isPinned = inspected != nil && inspected?.id == registry.pinnedID
        ZStack(alignment: .topLeading) {
            // Takes the pointer and the clicks, so the content beneath gets
            // neither while inspecting.
            Color.clear
                .contentShape(Rectangle())
                .onContinuousHover(coordinateSpace: .global) { phase in
                    switch phase {
                    case .active(let point): registry.pointer = point
                    case .ended: registry.pointer = nil
                    }
                }
                .onTapGesture(coordinateSpace: .global) { point in
                    registry.pin(at: point)
                }
                .pointerStyle(.rectSelection)

            if let inspected {
                let rect = inspected.frame.offsetBy(dx: -origin.x, dy: -origin.y)
                DevBoxHighlight(rect: rect, shown: inspected.shownFrame.offsetBy(dx: -origin.x, dy: -origin.y), padding: inspected.tag?.padding)
                    .allowsHitTesting(false)
                let inspection = DevInspection(inspected, path: registry.path(to: inspected), theme: theme)
                DevInspectorPanel(inspection: inspection, isPinned: isPinned) { key in
                    DevTools.shared.openInThemeEditor(key, openWindow: openWindow)
                }
                .onGeometryChange(for: CGSize.self, of: { $0.size }) { panelSize = $0 }
                .offset(Self.panelOffset(for: rect, panel: panelSize, in: bounds))
                .allowsHitTesting(isPinned)
            }
        }
    }

    /// Below the view when there's room, else above it, else inside the
    /// top of the window; never past an edge.
    static func panelOffset(for rect: CGRect, panel: CGSize, in bounds: CGSize, margin: CGFloat = 8) -> CGSize {
        let maxX = max(margin, bounds.width - panel.width - margin)
        let x = min(max(rect.minX, margin), maxX)
        var y = rect.maxY + margin
        if y + panel.height > bounds.height - margin {
            y = rect.minY - margin - panel.height
        }
        if y < margin {
            y = min(max(rect.minY + margin, margin), max(margin, bounds.height - panel.height - margin))
        }
        return CGSize(width: x, height: y)
    }
}

/// The inspected view's box: blue, with its padding in green, drawn
/// where it shows (`shown`: a row partly scrolled away is cut off where
/// its list ends).
struct DevBoxHighlight: View {
    let rect: CGRect
    let shown: CGRect
    let padding: EdgeInsets?

    var body: some View {
        Canvas { context, _ in
            context.clip(to: Path(shown))
            if let padding {
                context.fill(DevBox.paddingPath(rect, padding), with: .color(DevStyle.padding), style: FillStyle(eoFill: true))
            }
            context.fill(Path(rect), with: .color(DevStyle.highlightFill))
            context.stroke(Path(rect.insetBy(dx: 0.5, dy: 0.5)), with: .color(DevStyle.highlightStroke), lineWidth: 1)
        }
    }
}

struct DevInspectorPanel: View {
    let inspection: DevInspection
    let isPinned: Bool
    let openInThemeEditor: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(inspection.name)
                    .font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 8)
                Text(isPinned ? "pinned" : "click to pin")
                    .font(.system(size: 9.5))
                    .foregroundStyle(DevStyle.secondaryText)
            }
            if inspection.path.count > 1 {
                Text(inspection.path.joined(separator: " › "))
                    .font(.system(size: 9.5))
                    .foregroundStyle(DevStyle.secondaryText)
                    .lineLimit(2)
            }
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 3) {
                GridRow {
                    label("size")
                    value("\(Self.points(inspection.size.width)) × \(Self.points(inspection.size.height)) pt")
                }
                if let padding = inspection.padding {
                    GridRow {
                        label("padding")
                        value(Self.describe(padding))
                    }
                }
                if let font = inspection.font {
                    GridRow {
                        label("font")
                        value("\(font.family) \(Self.points(font.size)) pt \(font.weight)")
                    }
                }
            }
            if !inspection.tokens.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(inspection.tokens) { token in
                        tokenRow(token)
                    }
                }
                .padding(.top, 2)
            }
            Text(isPinned ? "Click it again to unpin · Esc leaves inspect mode" : "Esc leaves inspect mode")
                .font(.system(size: 9.5))
                .foregroundStyle(DevStyle.secondaryText)
        }
        .foregroundStyle(DevStyle.text)
        .textSelection(.enabled)
        .padding(10)
        .frame(minWidth: 240, maxWidth: 360, alignment: .leading)
        .fixedSize()
        .background(DevStyle.panel, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(DevStyle.panelBorder))
        .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
    }

    private func tokenRow(_ token: DevInspection.Token) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(ThemeColor(hex: token.hex)?.color ?? .clear)
                .frame(width: 12, height: 12)
                .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(DevStyle.panelBorder))
            Text(token.key)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(token.isKnown ? DevStyle.text : DevStyle.warning)
            Text(token.hex)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(DevStyle.secondaryText)
            if isPinned, token.isKnown {
                Spacer(minLength: 6)
                Button("Open in Theme Editor") { openInThemeEditor(token.key) }
                    .buttonStyle(.link)
                    .font(.system(size: 10))
            }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(DevStyle.secondaryText)
    }

    private func value(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, design: .monospaced))
    }

    static func points(_ value: CGFloat) -> String {
        value.rounded() == value ? String(Int(value)) : Double(value).formatted(.number.precision(.fractionLength(1)))
    }

    /// CSS order: top, right, bottom, left.
    static func describe(_ padding: EdgeInsets) -> String {
        [padding.top, padding.trailing, padding.bottom, padding.leading].map(points).joined(separator: " ")
    }
}

// MARK: - Layout Outlines

struct DevOutlines: View {
    let entries: [DevTagRegistry.Entry]
    /// The overlay's origin in window coordinates.
    let origin: CGPoint

    var body: some View {
        Canvas { context, _ in
            let rects = entries.map { $0.shownFrame.offsetBy(dx: -origin.x, dy: -origin.y) }
            var labels: [CGRect] = []
            for (entry, rect) in zip(entries, rects) {
                let name = entry.tag?.name ?? ""
                if let padding = entry.tag?.padding {
                    var padded = context
                    padded.clip(to: Path(rect))
                    let frame = entry.frame.offsetBy(dx: -origin.x, dy: -origin.y)
                    padded.fill(DevBox.paddingPath(frame, padding), with: .color(DevStyle.padding), style: FillStyle(eoFill: true))
                }
                context.stroke(Path(rect.insetBy(dx: 0.5, dy: 0.5)), with: .color(DevStyle.outline(for: name)), lineWidth: 1)
                guard rect.width >= 48, rect.height >= 12 else { continue }
                let size = entry.frame.size
                let text = context.resolve(
                    Text("\(name) \(DevInspectorPanel.points(size.width))×\(DevInspectorPanel.points(size.height))")
                        .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white)
                )
                let measured = text.measure(in: CGSize(width: rect.width - 4, height: 12))
                var box = CGRect(x: rect.minX + 1, y: rect.minY + 1, width: measured.width + 4, height: measured.height + 1)
                // Nested views that start at the same corner stack their labels.
                while labels.contains(where: { $0.intersects(box) }), box.maxY + box.height < rect.maxY {
                    box.origin.y += box.height
                }
                labels.append(box)
                context.fill(Path(box), with: .color(DevStyle.outline(for: name).opacity(0.85)))
                context.draw(text, in: box.insetBy(dx: 2, dy: 0.5))
            }
            for gap in DevLayoutGaps.gaps(between: rects) {
                var line = Path()
                line.move(to: gap.start)
                line.addLine(to: gap.end)
                context.stroke(line, with: .color(DevStyle.gap), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                let text = context.resolve(
                    Text(DevInspectorPanel.points(gap.length))
                        .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.white)
                )
                let measured = text.measure(in: CGSize(width: 60, height: 12))
                let mid = CGPoint(x: (gap.start.x + gap.end.x) / 2, y: (gap.start.y + gap.end.y) / 2)
                let box = CGRect(x: mid.x - measured.width / 2 - 2, y: mid.y - measured.height / 2, width: measured.width + 4, height: measured.height)
                context.fill(Path(roundedRect: box, cornerRadius: 2), with: .color(DevStyle.gap))
                context.draw(text, in: box.insetBy(dx: 2, dy: 0))
            }
        }
        .allowsHitTesting(false)
    }
}

/// The gaps between neighboring tagged views, as a browser's box model
/// shows margins: between siblings (views directly inside the same tagged
/// view), from each one to the nearest sibling on its right and below.
nonisolated enum DevLayoutGaps {
    struct Gap: Equatable, Sendable {
        var start: CGPoint
        var end: CGPoint
        var length: CGFloat { abs(end.x - start.x) + abs(end.y - start.y) }
    }

    /// Gaps of 0.5 points or less (views that touch) aren't drawn, nor
    /// gaps longer than `maxGap`.
    static func gaps(between rects: [CGRect], maxGap: CGFloat = 320) -> [Gap] {
        let indices = rects.indices.filter { !rects[$0].isNull && rects[$0].width > 0 && rects[$0].height > 0 }
        let parents = parents(of: rects, indices: indices)
        var gaps: [Gap] = []
        for a in indices {
            var right: (gap: CGFloat, overlap: ClosedRange<CGFloat>)?
            var below: (gap: CGFloat, overlap: ClosedRange<CGFloat>)?
            for b in indices where b != a && parents[b] == parents[a] {
                let ra = rects[a], rb = rects[b]
                let horizontalGap = rb.minX - ra.maxX
                let verticalOverlap = (max(ra.minY, rb.minY), min(ra.maxY, rb.maxY))
                if horizontalGap > 0.5, horizontalGap <= maxGap, verticalOverlap.1 - verticalOverlap.0 > 0,
                   horizontalGap < (right?.gap ?? .infinity) {
                    right = (horizontalGap, verticalOverlap.0...verticalOverlap.1)
                }
                let verticalGap = rb.minY - ra.maxY
                let horizontalOverlap = (max(ra.minX, rb.minX), min(ra.maxX, rb.maxX))
                if verticalGap > 0.5, verticalGap <= maxGap, horizontalOverlap.1 - horizontalOverlap.0 > 0,
                   verticalGap < (below?.gap ?? .infinity) {
                    below = (verticalGap, horizontalOverlap.0...horizontalOverlap.1)
                }
            }
            if let right {
                let y = (right.overlap.lowerBound + right.overlap.upperBound) / 2
                gaps.append(Gap(start: CGPoint(x: rects[a].maxX, y: y), end: CGPoint(x: rects[a].maxX + right.gap, y: y)))
            }
            if let below {
                let x = (below.overlap.lowerBound + below.overlap.upperBound) / 2
                gaps.append(Gap(start: CGPoint(x: x, y: rects[a].maxY), end: CGPoint(x: x, y: rects[a].maxY + below.gap)))
            }
        }
        return gaps
    }

    /// For each rect, the smallest other rect containing it (the one
    /// listed first when two are the same), or nil at the top.
    static func parents(of rects: [CGRect], indices: [Int]) -> [Int: Int] {
        var parents: [Int: Int] = [:]
        for child in indices {
            var best: Int?
            for candidate in indices where candidate != child {
                let outer = rects[candidate], inner = rects[child]
                guard outer.insetBy(dx: -0.5, dy: -0.5).contains(inner) else { continue }
                let same = abs(outer.width - inner.width) < 0.5 && abs(outer.height - inner.height) < 0.5
                // Of two identical rects, the first listed is the parent.
                if same && candidate > child { continue }
                if let current = best {
                    let area = outer.width * outer.height
                    let currentArea = rects[current].width * rects[current].height
                    if area < currentArea || (area == currentArea && candidate > current) { best = candidate }
                } else {
                    best = candidate
                }
            }
            parents[child] = best
        }
        return parents
    }
}

enum DevBox {
    /// The band between `rect` and its content box (`rect` less `padding`),
    /// filled with the even-odd rule.
    static func paddingPath(_ rect: CGRect, _ padding: EdgeInsets) -> Path {
        var path = Path(rect)
        let inner = CGRect(
            x: rect.minX + padding.leading,
            y: rect.minY + padding.top,
            width: max(0, rect.width - padding.leading - padding.trailing),
            height: max(0, rect.height - padding.top - padding.bottom)
        )
        path.addRect(inner)
        return path
    }
}

// MARK: - Style

/// The tools' own colors. They're fixed rather than theme tokens, so the
/// tools read the same over every theme and never show up in what they
/// inspect (the one place Vela draws colors that aren't from the theme).
enum DevStyle {
    static let panel = Color(red: 0.10, green: 0.11, blue: 0.14).opacity(0.95)
    static let panelBorder = Color.white.opacity(0.16)
    static let text = Color(white: 0.94)
    static let secondaryText = Color(white: 0.64)
    static let warning = Color(red: 1, green: 0.74, blue: 0.32)
    static let highlightFill = Color(red: 0.26, green: 0.56, blue: 1).opacity(0.2)
    static let highlightStroke = Color(red: 0.32, green: 0.62, blue: 1)
    static let padding = Color(red: 0.42, green: 0.80, blue: 0.40).opacity(0.3)
    static let gap = Color(red: 0.92, green: 0.28, blue: 0.68)

    private static let outlines: [Color] = [
        Color(red: 0.32, green: 0.62, blue: 1),
        Color(red: 1, green: 0.55, blue: 0.2),
        Color(red: 0.35, green: 0.78, blue: 0.45),
        Color(red: 0.75, green: 0.45, blue: 1),
        Color(red: 0.95, green: 0.35, blue: 0.4),
        Color(red: 0.2, green: 0.75, blue: 0.8),
    ]

    /// The same color for every view with the same name.
    static func outline(for name: String) -> Color {
        var hash: UInt32 = 5381
        for byte in name.utf8 { hash = (hash &* 33) &+ UInt32(byte) }
        return outlines[Int(hash % UInt32(outlines.count))]
    }
}

#endif
