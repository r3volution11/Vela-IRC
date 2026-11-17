// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import VelaStore

/// What a ``JSONCodeTextView`` asks of its owner.
@MainActor
protocol JSONCodeTextViewOwner: AnyObject {
    /// ⌃Space, ⌥Esc or F5.
    func codeViewRequestsCompletion(_ view: JSONCodeTextView)
    /// Esc. Returns true when something (the completion list, a hover card)
    /// was closed.
    func codeViewCancel(_ view: JSONCodeTextView) -> Bool
    /// The pointer rests at `point` (text view coordinates) over character
    /// `index`, or left the text (`nil`).
    func codeView(_ view: JSONCodeTextView, pointerAt point: NSPoint?, characterIndex: Int?)
    /// The view lost keyboard focus.
    func codeViewDidResignFocus(_ view: JSONCodeTextView)
    /// The view was added to a window, or removed from one.
    func codeViewDidMoveToWindow(_ view: JSONCodeTextView)
    /// A keystroke typed `text` (after quote pairing moved the caret).
    func codeView(_ view: JSONCodeTextView, didType text: String)
    /// The line index for the gutter.
    func lineIndex(for view: JSONCodeTextView) -> JSONLineIndex
}

/// A plain-text code view for JSONC: a line-number gutter with problem
/// markers, squiggly underlines, a current-line highlight and the find bar,
/// with every kind of macOS text checking and substitution off. TextKit 1,
/// so colors can be temporary attributes and layout stays non-contiguous
/// for large files.
final class JSONCodeTextView: NSTextView {
    weak var owner: JSONCodeTextViewOwner?

    /// Squiggles, by severity; drawn over the text.
    var diagnostics: [SettingsDiagnostic] = [] {
        didSet { needsDisplay = true }
    }

    struct Palette {
        var background: NSColor
        var gutterForeground: NSColor
        var gutterActiveForeground: NSColor
        var gutterBorder: NSColor
        var currentLine: NSColor
        var error: NSColor
        var warning: NSColor
        var info: NSColor
    }

    var palette = Palette(
        background: .textBackgroundColor, gutterForeground: .secondaryLabelColor,
        gutterActiveForeground: .labelColor, gutterBorder: .separatorColor, currentLine: .clear,
        error: .systemRed, warning: .systemOrange, info: .secondaryLabelColor
    ) {
        didSet {
            backgroundColor = palette.background
            needsDisplay = true
        }
    }

    /// Width of the line-number gutter, including its padding.
    private(set) var gutterWidth: CGFloat = 40
    /// Space between the gutter and the text.
    let gutterGap: CGFloat = 10
    /// Space after the text.
    let trailingPadding: CGFloat = 14
    let verticalInset: CGFloat = 8

    /// Lines get a gutter number; the defaults pane shows them too.
    var showsCurrentLine = true

    private var hoverTrackingArea: NSTrackingArea?

    // MARK: Setup

    static func make(editable: Bool) -> (JSONCodeTextView, NSScrollView) {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = true
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsetsZero

        let textView = JSONCodeTextView(usingTextLayoutManager: false)
        textView.layoutManager?.allowsNonContiguousLayout = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.lineFragmentPadding = 2
        textView.textContainerInset = NSSize(width: 0, height: textView.verticalInset)

        textView.isEditable = editable
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsImageEditing = false
        textView.allowsUndo = editable
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.usesFontPanel = false
        textView.usesRuler = false
        textView.usesInspectorBar = false
        textView.displaysLinkToolTips = false
        textView.allowsCharacterPickerTouchBarItem = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.writingToolsBehavior = .none
        textView.inlinePredictionType = .no
        textView.focusRingType = .none
        textView.drawsBackground = true
        textView.showsCurrentLine = editable
        textView.setAccessibilityLabel(editable ? "settings.json" : "Default settings")

        scrollView.documentView = textView
        return (textView, scrollView)
    }

    // MARK: Geometry

    /// Sizes the gutter for `lineCount` lines in `font`.
    func updateGutter(lineCount: Int) {
        let digits = max(3, String(lineCount).count)
        let digitWidth = ("0" as NSString).size(withAttributes: [.font: gutterFont]).width
        let width = ceil(CGFloat(digits) * digitWidth + 22)
        guard abs(width - gutterWidth) > 0.5 else { return }
        gutterWidth = width
        layoutContainer()
    }

    /// The text's baseline from the top of a line fragment.
    private var textBaseline: CGFloat {
        guard let layoutManager, let font else { return 12 }
        return layoutManager.defaultBaselineOffset(for: font)
    }

    var gutterFont: NSFont {
        let size = max(9, (font?.pointSize ?? 12) - 1)
        return NSFont.monospacedDigitSystemFont(ofSize: size, weight: .regular)
    }

    override var textContainerOrigin: NSPoint {
        NSPoint(x: gutterWidth + gutterGap, y: verticalInset)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutContainer()
    }

    private func layoutContainer() {
        guard let container = textContainer else { return }
        let width = max(40, frame.width - gutterWidth - gutterGap - trailingPadding)
        if abs(container.size.width - width) > 0.5 {
            container.size = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        }
        needsDisplay = true
    }

    /// The rect of `range`'s first line fragment, in this view's coordinates.
    func rect(forCharacterRange range: NSRange) -> NSRect? {
        guard let layoutManager, let textContainer else { return nil }
        let length = (string as NSString).length
        let clamped = NSRange(location: min(range.location, length), length: max(0, min(range.length, length - min(range.location, length))))
        var glyphRange = layoutManager.glyphRange(forCharacterRange: clamped, actualCharacterRange: nil)
        if glyphRange.length == 0 {
            if clamped.location >= length, length > 0, layoutManager.extraLineFragmentTextContainer == nil {
                glyphRange = NSRange(location: max(0, layoutManager.numberOfGlyphs - 1), length: 1)
                var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
                rect.origin.x = rect.maxX
                rect.size.width = 1
                return rect.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
            }
            if clamped.location >= length {
                let extra = layoutManager.extraLineFragmentRect
                if !extra.isEmpty {
                    return NSRect(x: extra.minX, y: extra.minY, width: 1, height: extra.height)
                        .offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
                }
            }
            glyphRange.length = 0
        }
        var result: NSRect?
        layoutManager.enumerateEnclosingRects(
            forGlyphRange: glyphRange,
            withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
            in: textContainer
        ) { rect, stop in
            result = rect
            stop.pointee = true
        }
        return result?.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
    }

    /// The character under `point` (view coordinates), or nil when the
    /// point isn't over text.
    func characterIndex(at point: NSPoint) -> Int? {
        guard let layoutManager, let textContainer else { return nil }
        let containerPoint = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        guard containerPoint.x >= 0 else { return nil }
        var fraction: CGFloat = 0
        let glyph = layoutManager.glyphIndex(for: containerPoint, in: textContainer, fractionOfDistanceThroughGlyph: &fraction)
        guard glyph < layoutManager.numberOfGlyphs else { return nil }
        let glyphRect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer)
        guard glyphRect.insetBy(dx: -1, dy: 0).contains(containerPoint) else { return nil }
        return layoutManager.characterIndexForGlyph(at: glyph)
    }

    // MARK: Drawing

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        drawCurrentLine(in: rect)
        drawGutter(in: rect)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawSquiggles(in: dirtyRect)
    }

    private var caretLineRect: NSRect? {
        guard showsCurrentLine, isEditable, let layoutManager, let textContainer else { return nil }
        let selection = selectedRange()
        guard selection.length == 0 else { return nil }
        let text = string as NSString
        if selection.location >= text.length, !layoutManager.extraLineFragmentRect.isEmpty,
           text.length == 0 || [0x0A, 0x0D].contains(text.character(at: text.length - 1))
        {
            return layoutManager.extraLineFragmentRect.offsetBy(dx: 0, dy: textContainerOrigin.y)
        }
        guard layoutManager.numberOfGlyphs > 0 else { return nil }
        let lineRange = text.lineRange(for: NSRange(location: min(selection.location, text.length), length: 0))
        let glyphs = layoutManager.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
        guard glyphs.length > 0 else { return nil }
        var union = NSRect.null
        layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { rect, _, _, _, _ in
            union = union.union(rect)
        }
        _ = textContainer
        return union.isNull ? nil : union.offsetBy(dx: 0, dy: textContainerOrigin.y)
    }

    private func drawCurrentLine(in rect: NSRect) {
        guard window?.firstResponder === self, var line = caretLineRect else { return }
        line.origin.x = 0
        line.size.width = bounds.width
        guard line.intersects(rect) else { return }
        palette.currentLine.setFill()
        line.fill()
    }

    private func drawGutter(in rect: NSRect) {
        let gutter = NSRect(x: 0, y: rect.minY, width: gutterWidth, height: rect.height)
        guard gutter.intersects(rect), let layoutManager, let textContainer, let owner else { return }
        palette.background.setFill()
        gutter.fill()

        let index = owner.lineIndex(for: self)
        let text = string as NSString
        let length = text.length
        let origin = textContainerOrigin
        let visible = rect.offsetBy(dx: -origin.x, dy: -origin.y)
        let glyphs = layoutManager.glyphRange(forBoundingRect: visible, in: textContainer)
        let characters = layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)

        // The most severe problem starting on each visible line.
        var markers: [Int: SettingsDiagnostic.Severity] = [:]
        for diagnostic in diagnostics {
            let line = index.line(containing: diagnostic.range.location)
            if let current = markers[line], current <= diagnostic.severity { continue }
            markers[line] = diagnostic.severity
        }

        let caretLine = window?.firstResponder === self ? index.line(containing: selectedRange().location) : -1
        let font = gutterFont
        let numberWidth = gutterWidth - 8
        var line = index.line(containing: characters.location)
        let lastCharacter = characters.location + characters.length
        while line < index.lineCount {
            let start = index.start(ofLine: line)
            if start > lastCharacter { break }
            let fragment: NSRect
            if start >= length {
                // The empty line after a final line break.
                let extra = layoutManager.extraLineFragmentRect
                guard !extra.isEmpty, length == 0 || start == length else { break }
                fragment = extra
            } else {
                fragment = layoutManager.lineFragmentRect(forGlyphAt: layoutManager.glyphIndexForCharacter(at: start), effectiveRange: nil)
            }
            // One font throughout, so every line's baseline sits alike.
            let baseline = textBaseline
            let top = fragment.minY + origin.y
            if top > rect.maxY { break }
            let number = "\(line + 1)" as NSString
            let color = line == caretLine ? palette.gutterActiveForeground : palette.gutterForeground
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            let size = number.size(withAttributes: attributes)
            let y = top + baseline - font.ascender
            number.draw(at: NSPoint(x: numberWidth - size.width, y: y), withAttributes: attributes)

            if let severity = markers[line] {
                let diameter: CGFloat = 6
                let marker = NSRect(x: 5, y: top + baseline - font.ascender + (size.height - diameter) / 2, width: diameter, height: diameter)
                self.color(for: severity).setFill()
                NSBezierPath(ovalIn: marker).fill()
            }
            line += 1
        }
    }

    func color(for severity: SettingsDiagnostic.Severity) -> NSColor {
        switch severity {
        case .error: palette.error
        case .warning: palette.warning
        case .info: palette.info
        }
    }

    private func drawSquiggles(in rect: NSRect) {
        guard !diagnostics.isEmpty, let layoutManager, let textContainer else { return }
        let origin = textContainerOrigin
        let visible = rect.offsetBy(dx: -origin.x, dy: -origin.y)
        let glyphs = layoutManager.glyphRange(forBoundingRect: visible, in: textContainer)
        let characters = layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        let length = (string as NSString).length
        // Draw the least severe first so errors end up on top.
        for diagnostic in diagnostics.sorted(by: { $0.severity > $1.severity }) {
            let range = NSIntersectionRange(diagnostic.range, NSRange(location: 0, length: length))
            guard range.length > 0, NSIntersectionRange(range, characters).length > 0 || NSLocationInRange(range.location, characters) else { continue }
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let color = color(for: diagnostic.severity)
            layoutManager.enumerateEnclosingRects(
                forGlyphRange: glyphRange,
                withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                in: textContainer
            ) { lineRect, _ in
                let underline = lineRect.offsetBy(dx: origin.x, dy: origin.y)
                guard underline.intersects(rect.insetBy(dx: 0, dy: -4)) else { return }
                if diagnostic.severity == .info {
                    Self.drawDots(under: underline, color: color)
                } else {
                    Self.drawWave(under: underline, color: color)
                }
            }
        }
    }

    private static func drawWave(under rect: NSRect, color: NSColor) {
        let path = NSBezierPath()
        let amplitude: CGFloat = 1.5
        let period: CGFloat = 4
        let y = rect.maxY - amplitude - 0.5
        var x = rect.minX
        path.move(to: NSPoint(x: x, y: y))
        var up = true
        while x < rect.maxX {
            let next = min(x + period / 2, rect.maxX)
            path.line(to: NSPoint(x: next, y: up ? y - amplitude : y + amplitude))
            up.toggle()
            x = next
        }
        path.lineWidth = 1
        path.lineJoinStyle = .round
        color.setStroke()
        path.stroke()
    }

    private static func drawDots(under rect: NSRect, color: NSColor) {
        let y = rect.maxY - 2
        var x = rect.minX
        color.setFill()
        while x < rect.maxX {
            NSBezierPath(ovalIn: NSRect(x: x, y: y - 0.75, width: 1.5, height: 1.5)).fill()
            x += 3
        }
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        let oldLine = caretLineRect
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        // Repaint the old and new current line (and their gutter numbers).
        if let oldLine { setNeedsDisplay(NSRect(x: 0, y: oldLine.minY, width: bounds.width, height: oldLine.height)) }
        if let newLine = caretLineRect { setNeedsDisplay(NSRect(x: 0, y: newLine.minY, width: bounds.width, height: newLine.height)) }
    }

    // MARK: Focus

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { needsDisplay = true }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted {
            needsDisplay = true
            owner?.codeViewDidResignFocus(self)
        }
        return accepted
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        owner?.codeViewDidMoveToWindow(self)
    }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .control, event.charactersIgnoringModifiers == " " {
            owner?.codeViewRequestsCompletion(self)
            return
        }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let key = event.charactersIgnoringModifiers?.lowercased()
        let action: NSTextFinder.Action? = switch (flags, key) {
        case ([.command], "f"): .showFindInterface
        case ([.command, .option], "f"): isEditable ? .showReplaceInterface : .showFindInterface
        case ([.command], "g"): .nextMatch
        case ([.command, .shift], "g"): .previousMatch
        case ([.command], "e"): .setSearchString
        default: nil
        }
        if let action {
            let item = NSMenuItem()
            item.tag = action.rawValue
            performTextFinderAction(item)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    /// ⌥Esc and F5: the standard "complete" command opens Vela's list.
    override func complete(_ sender: Any?) {
        owner?.codeViewRequestsCompletion(self)
    }

    override func cancelOperation(_ sender: Any?) {
        // Esc closes the completion list or a hover card; it doesn't open
        // the system's completion menu.
        _ = owner?.codeViewCancel(self)
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        let typed = (string as? String) ?? (string as? NSAttributedString)?.string ?? ""
        if isEditable, typed == "\"", replacementRange.location == NSNotFound,
           selectedRange().length == 0, !hasMarkedText()
        {
            let caret = selectedRange().location
            switch JSONTyping.quoteAction(in: self.string as NSString, at: caret) {
            case .insertSingle:
                super.insertText(string, replacementRange: replacementRange)
            case .skipClosing:
                setSelectedRange(NSRange(location: caret + 1, length: 0))
            case .insertPair:
                super.insertText("\"\"", replacementRange: replacementRange)
                setSelectedRange(NSRange(location: caret + 1, length: 0))
            }
        } else {
            super.insertText(string, replacementRange: replacementRange)
        }
        if isEditable, !hasMarkedText() {
            owner?.codeView(self, didType: typed)
        }
    }

    // MARK: Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let point = convert(event.locationInWindow, from: nil)
        owner?.codeView(self, pointerAt: point, characterIndex: characterIndex(at: point))
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        owner?.codeView(self, pointerAt: nil, characterIndex: nil)
    }
}
