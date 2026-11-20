// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import Testing
import VelaCore
import VelaIntelligence
import VelaStore
import VelaTheme
@testable import VelaUI

extension LinkSelectionTests {
    /// The user (nick) menu where people right-click it: a nick in a
    /// message (each layout), a member mentioned in a message's text, a
    /// message's menu (under the author's name) and the member list. Demo
    /// content: doug owns #vela (marisol and kenji are ops, ada and theo
    /// voiced) and is a regular member of #vela-offtopic.
    ///
    /// Menus are asked for as AppKit does on a right-click, never opened:
    /// a real menu's tracking loop can end the test run. Nested in the
    /// serialized `LinkSelectionTests`, since message text uses
    /// `LinkClickMonitor.shared`.
    @MainActor
    @Suite("User menus")
    struct UserMenuUITests {
        private static let app: AppModel = {
            let app = AppModel.demo()
            app.settings[.mediaShowLinkCards] = false
            app.settings[.mediaAutoLoad] = false
            return app
        }()

        private final class Hosted {
            let window: NSWindow
            let host: NSView
            let uiState: UIState
            /// The selectable texts, top to bottom.
            let texts: [NSView]

            init(window: NSWindow, host: NSView, uiState: UIState, texts: [NSView]) {
                self.window = window
                self.host = host
                self.uiState = uiState
                self.texts = texts
            }

            var regionViews: [LinkPointerRegionView] {
                UserMenuUITests.findAll(in: host) { $0 is LinkPointerRegionView }.compactMap { $0 as? LinkPointerRegionView }
            }

            /// The middle of the characters at UTF-16 `range` of the text
            /// under `regionView`, in the window.
            func point(of range: Range<Int>, in regionView: LinkPointerRegionView) throws -> CGPoint {
                let glyphs = try #require(regionView.words?.glyphs)
                let rects = range.compactMap { glyphs.rect(forOffset: $0) }
                let first = try #require(rects.first)
                let rect = rects.dropFirst().reduce(first) { $0.union($1) }
                return regionView.convert(CGPoint(x: rect.midX, y: rect.midY), to: nil)
            }

            /// The middle of `word` (its first occurrence) in the text under
            /// `regionView`, in the window.
            func point(of word: String, in regionView: LinkPointerRegionView) throws -> CGPoint {
                let text = try #require(regionView.words?.text)
                let range = try #require(text.range(of: word))
                let lower = text.utf16.distance(from: text.startIndex, to: range.lowerBound)
                return try point(of: lower..<(lower + word.utf16.count), in: regionView)
            }

            /// A window point `x` from the leading edge of `text`, `dy`
            /// above its top (negative: into its first line).
            func point(above text: NSView, x: CGFloat, dy: CGFloat) -> CGPoint {
                let frame = text.convert(text.bounds, to: nil)
                return CGPoint(x: frame.minX + x, y: frame.maxY + dy)
            }

            func close() {
                window.orderOut(nil)
                window.contentView = nil
            }
        }

        private static let translationContext = TranslationContext(target: Locale.Language(identifier: "en"), isAutomatic: false, isDemo: true)

        private func session() throws -> NetworkSession {
            try #require(Self.app.sessions.first)
        }

        private func buffer(_ name: String) throws -> BufferModel {
            try #require(session().buffer(named: name))
        }

        /// `controller`, when given, is already prepared (as the list does).
        private func host(
            _ lines: [ChatLine], in buffer: BufferModel, layout: ChatLayout, controller given: MessageListController? = nil
        ) async throws -> Hosted {
            let app = Self.app
            let session = try session()
            let controller = given ?? MessageListController(buffer: buffer, session: session)
            let uiState = UIState()
            let theme = ResolvedTheme.fallbackLight
            var style = ChatStyle(settings: app.settings)
            style.layout = layout
            if given == nil {
                controller.textCache.prepare(
                    palette: MessageTextPalette(theme: theme, style: style),
                    options: MessageTextOptions(renderFormatting: style.renderFormatting, selfNick: session.nick, channelTypes: session.isupport.channelTypes)
                )
            }
            let view = ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(lines) { line in
                        DisplayItemRow(item: .line(LineItem(line: line, isContinuation: false, reply: nil)))
                    }
                }
            }
            .frame(width: 640, height: 360, alignment: .topLeading)
            .environment(controller)
            .environment(app)
            .environment(uiState)
            .environment(IntelligenceServices.demo())
            .environment(TranslationStore())
            .environment(\.translationContext, Self.translationContext)
            .environment(\.theme, theme)
            .environment(\.chatStyle, style)
            .environment(\.nickColorBuffer, buffer)
            return try await show(view, uiState: uiState, size: CGSize(width: 640, height: 360))
        }

        private func show(_ view: some View, uiState: UIState, size: CGSize) async throws -> Hosted {
            let host = NSHostingView(rootView: view)
            let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -8000, y: -8000), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            window.orderFrontRegardless()
            try await Task.sleep(for: .milliseconds(200))
            let texts = Self.findAll(in: host) { NSStringFromClass(type(of: $0)).contains("TextInteraction") }
                .sorted { $0.convert($0.bounds, to: nil).midY > $1.convert($1.bounds, to: nil).midY }
            return Hosted(window: window, host: host, uiState: uiState, texts: texts)
        }

        fileprivate static func findAll(in view: NSView, where matches: (NSView) -> Bool) -> [NSView] {
            (matches(view) ? [view] : []) + view.subviews.flatMap { findAll(in: $0, where: matches) }
        }

        // MARK: Menus

        private static var eventNumber = 12000

        private func rightClick(at point: CGPoint, in hosted: Hosted) -> NSEvent {
            Self.eventNumber += 1
            return NSEvent.mouseEvent(
                with: .rightMouseDown, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: hosted.window.windowNumber,
                context: nil, eventNumber: Self.eventNumber, clickCount: 1, pressure: 1
            )!
        }

        private struct ContextMenu {
            var view: NSView?
            var menu: NSMenu?
            var items: [String] { menu?.items.filter { !$0.isSeparatorItem }.map(\.title) ?? [] }

            func submenu(_ title: String) -> [String] {
                menu?.items.first { $0.title == title }?.submenu?.items.filter { !$0.isSeparatorItem }.map(\.title) ?? []
            }

            func perform(_ title: String) throws {
                let menu = try #require(menu)
                let index = menu.indexOfItem(withTitle: title)
                try #require(index >= 0, "\(title): \(items)")
                menu.performActionForItem(at: index)
            }
        }

        /// The menu a right-click at `point` opens, asked for as AppKit
        /// does: the view it lands on, else the first view around it with
        /// one. The views over text see the click as the current event.
        private func contextMenu(at point: CGPoint, in hosted: Hosted) -> ContextMenu {
            let event = rightClick(at: point, in: hosted)
            let regionViews = hosted.regionViews
            for view in regionViews {
                view.currentEventType = { event.type }
                view.currentModifiers = { event.modifierFlags }
            }
            defer {
                for view in regionViews {
                    view.currentEventType = { NSApplication.shared.currentEvent?.type }
                    view.currentModifiers = { NSApplication.shared.currentEvent?.modifierFlags ?? [] }
                }
            }
            let target = hosted.window.contentView?.superview?.hitTest(point)
            var responder = target
            while let view = responder {
                if let menu = view.menu(for: event) { return ContextMenu(view: target, menu: menu) }
                responder = view.superview
            }
            return ContextMenu(view: target, menu: nil)
        }

        private func line(_ nick: String, _ text: String) -> ChatLine {
            ChatLine(msgid: UUID().uuidString, kind: .message, nick: nick, userHost: "\(nick)@user/\(nick)", text: text)
        }

        /// What a user menu for someone else in #vela, as its owner, starts with.
        private static let userMenuStart = ["Message", "Mention", "Whois", "Ping", "CTCP"]
        /// Items only a message's menu has.
        private static let messageOnly = ["Reply", "Copy Text"]

        // MARK: Nicks in messages

        @Test func theNameInAModernHeaderOpensTheUserMenu() async throws {
            let hosted = try await host([line("marisol", "the build is green again")], in: buffer("#vela"), layout: .grouped)
            defer { hosted.close() }
            let text = try #require(hosted.texts.first)
            let menu = contextMenu(at: hosted.point(above: text, x: 12, dy: 8), in: hosted)
            #expect(Array(menu.items.prefix(5)) == Self.userMenuStart, "\(menu.items)")
            // doug owns #vela; marisol is an op.
            for item in ["Deop", "Kick", "Kick with Reason…", "Ban", "Kick + Ban", "Ignore", "Copy Host Mask"] {
                #expect(menu.items.contains(item), "\(item): \(menu.items)")
            }
            #expect(Self.messageOnly.allSatisfy { !menu.items.contains($0) }, "\(menu.items)")
            #expect(menu.submenu("CTCP") == ["Version", "Time", "Client Info"])
            // The text itself still opens the message's menu.
            let onText = contextMenu(at: hosted.point(above: text, x: 200, dy: -7), in: hosted)
            #expect(onText.items.contains("Reply"), "\(onText.items)")
        }

        @Test func theNickColumnOpensTheUserMenu() async throws {
            let hosted = try await host([line("ada", "columns line up nicely")], in: buffer("#vela"), layout: .columns)
            defer { hosted.close() }
            let text = try #require(hosted.texts.first)
            // Left of the text, in the nick column.
            let menu = contextMenu(at: hosted.point(above: text, x: -30, dy: -7), in: hosted)
            #expect(Array(menu.items.prefix(5)) == Self.userMenuStart, "\(menu.items)")
            #expect(menu.items.contains("Devoice"), "\(menu.items)")
            #expect(!menu.items.contains("Reply"), "\(menu.items)")
        }

        @Test func theNickInAClassicLineOpensTheUserMenu() async throws {
            let hosted = try await host([line("marisol", "morning all")], in: buffer("#vela"), layout: .classic)
            defer { hosted.close() }
            let regionView = try #require(hosted.regionViews.first)
            #expect(regionView.words?.text.hasPrefix("<marisol> ") == true)
            let menu = contextMenu(at: try hosted.point(of: "marisol", in: regionView), in: hosted)
            #expect(menu.view === regionView)
            #expect(menu.menu?.title == "marisol")
            #expect(Array(menu.items.prefix(5)) == Self.userMenuStart, "\(menu.items)")
            #expect(menu.items.contains("Deop"), "\(menu.items)")
            #expect(menu.submenu("CTCP") == ["Version", "Time", "Client Info"])
            // Another word gets the message's menu.
            let onWord = contextMenu(at: try hosted.point(of: "all", in: regionView), in: hosted)
            #expect(onWord.items.contains("Reply"), "\(onWord.items)")
        }

        @Test func aMemberMentionedInTheTextOpensTheirMenu() async throws {
            let hosted = try await host([line("marisol", "kenji: can you check what priya said about the sidebar?")], in: buffer("#vela"), layout: .grouped)
            defer { hosted.close() }
            let regionView = try #require(hosted.regionViews.first)
            let onKenji = contextMenu(at: try hosted.point(of: "kenji", in: regionView), in: hosted)
            #expect(onKenji.menu?.title == "kenji")
            #expect(Array(onKenji.items.prefix(5)) == Self.userMenuStart, "\(onKenji.items)")
            let onPriya = contextMenu(at: try hosted.point(of: "priya", in: regionView), in: hosted)
            #expect(onPriya.menu?.title == "priya")
            // priya has no rank: Op and Voice, and the moderation items.
            #expect(onPriya.items.contains("Op"), "\(onPriya.items)")
            #expect(onPriya.items.contains("Kick"), "\(onPriya.items)")
            // Words that aren't members get the message's menu.
            let onWord = contextMenu(at: try hosted.point(of: "sidebar", in: regionView), in: hosted)
            #expect(onWord.items.contains("Reply"), "\(onWord.items)")
            #expect(onWord.menu?.title != "sidebar")
        }

        /// With nicks colored in messages, a word is colored exactly when a
        /// right-click on it opens that person's menu; the text reads (and
        /// VoiceOver says) the same.
        @Test func theNicksColoredInTheTextAreTheOnesWithAMenu() async throws {
            let session = try session()
            let channel = try buffer("#vela")
            let theme = ResolvedTheme.fallbackLight
            let style = ChatStyle(settings: Self.app.settings)
            let controller = MessageListController(buffer: channel, session: session)
            controller.prepareText(
                palette: MessageTextPalette(theme: theme, style: style),
                options: MessageTextOptions(
                    renderFormatting: style.renderFormatting, selfNick: session.nick, channelTypes: session.isupport.channelTypes,
                    colorsNicks: true, caseMapping: session.isupport.caseMapping
                ),
                nickChangeCount: channel.nickChangeCount
            )
            let message = line("marisol", "kenji: can you check what priya said about the sidebar, doug?")
            let hosted = try await host([message], in: channel, layout: .grouped, controller: controller)
            defer { hosted.close() }
            let regionView = try #require(hosted.regionViews.first)

            // What the row drew.
            let rendered = controller.textCache.rendered(message)
            func color(of word: String) -> Color? {
                guard let range = rendered.attributed.range(of: word) else { return nil }
                return rendered.attributed[range].runs.first?.foregroundColor ?? nil
            }
            for word in ["kenji", "priya"] {
                #expect(color(of: word) == theme.nickColor(for: word, in: channel).color, "\(word)")
                let menu = contextMenu(at: try hosted.point(of: word, in: regionView), in: hosted)
                #expect(menu.menu?.title == word, "\(word): \(menu.items)")
            }
            for word in ["check", "sidebar"] {
                #expect(color(of: word) == nil, "\(word)")
                let menu = contextMenu(at: try hosted.point(of: word, in: regionView), in: hosted)
                #expect(menu.items.contains("Reply"), "\(word): \(menu.items)")
            }
            // A mention of us is a mention.
            #expect(color(of: "doug") == theme[ThemeKey.chatMention])
            #expect(rendered.plain == message.text)
        }

        /// In a conversation, the person it's with is the nick colored in
        /// the text, and theirs is the menu a right-click on it opens.
        @Test func thePersonAConversationIsWithHasTheirMenuInTheText() throws {
            let session = try session()
            let query = BufferModel(id: BufferID(networkID: session.id, foldedName: "wren"), name: "wren", kind: .query)
            let actions = UserMenuActions(app: Self.app, uiState: UIState(), session: session, buffer: query)
            let message = line("wren", "WREN here, ask kenji")
            let menu = actions.menu(forWord: "WREN", range: 0..<4, in: message, prefixLength: 0)
            #expect(menu?.targets.map(\.nick) == ["wren"])
            #expect(menu?.menu.sections.flatMap { $0 }.isEmpty == false)
            // Someone else named in a conversation is just a word there.
            #expect(actions.menu(forWord: "kenji", range: 15..<20, in: message, prefixLength: 0) == nil)
        }

        @Test func userMenuItemsDoTheirThing() async throws {
            Self.app.settings[.moderationKickReason] = "Take a break"
            defer { Self.app.settings.reset(.moderationKickReason) }
            let hosted = try await host([line("marisol", "theo, could you look?")], in: buffer("#vela"), layout: .grouped)
            defer { hosted.close() }
            let regionView = try #require(hosted.regionViews.first)
            let point = try hosted.point(of: "theo", in: regionView)
            try contextMenu(at: point, in: hosted).perform("Mention")
            #expect(hosted.uiState.mentionRequest?.nick == "theo")
            #expect(hosted.uiState.mentionRequest?.bufferID == (try buffer("#vela")).id)
            try contextMenu(at: point, in: hosted).perform("Kick + Ban with Reason…")
            let request = try #require(hosted.uiState.kickRequest)
            #expect(request.nicks == ["theo"])
            #expect(request.ban)
            #expect(request.reason == "Take a break")
            try contextMenu(at: point, in: hosted).perform("Message")
            #expect(Self.app.selectedBuffer?.name == "theo")
            #expect(Self.app.selectedBuffer?.kind == .query)
        }

        @Test func theMessageMenuHasTheAuthorsSubmenu() async throws {
            let hosted = try await host([line("kenji", "pushed a fix for the tab scroller")], in: buffer("#vela"), layout: .grouped)
            defer { hosted.close() }
            let text = try #require(hosted.texts.first)
            let frame = text.convert(text.bounds, to: nil)
            let beside = CGPoint(x: hosted.host.convert(hosted.host.bounds, to: nil).maxX - 30, y: frame.maxY - 7)
            let menu = contextMenu(at: beside, in: hosted)
            // Today's items stay...
            for item in ["Reply", "Copy Text", "Copy Nick", "Message kenji", "Whois kenji"] {
                #expect(menu.items.contains(item), "\(item): \(menu.items)")
            }
            // ...and the user menu is under kenji's name.
            let submenu = menu.submenu("kenji")
            #expect(Array(submenu.prefix(5)) == Self.userMenuStart, "\(submenu)")
            #expect(submenu.contains("Deop"), "\(submenu)")
            #expect(submenu.contains("Kick + Ban"), "\(submenu)")
        }

        @Test func asARegularMemberThereIsNoModeration() async throws {
            // doug has no rank in #vela-offtopic.
            let hosted = try await host([line("marisol", "lunch?")], in: buffer("#vela-offtopic"), layout: .grouped)
            defer { hosted.close() }
            let text = try #require(hosted.texts.first)
            let menu = contextMenu(at: hosted.point(above: text, x: 12, dy: 8), in: hosted)
            #expect(Array(menu.items.prefix(5)) == Self.userMenuStart, "\(menu.items)")
            for item in ["Op", "Deop", "Voice", "Kick", "Ban", "Kick + Ban", "Quiet"] {
                #expect(!menu.items.contains(item), "\(item): \(menu.items)")
            }
        }

        // MARK: Member list

        private func hostMemberList(_ buffer: BufferModel, selection: MemberSelection = MemberSelection()) async throws -> Hosted {
            let app = Self.app
            let uiState = UIState()
            let view = MemberListView(buffer: buffer, session: try session(), selection: selection)
                .frame(width: 200, height: 420)
                .environment(app)
                .environment(uiState)
                .environment(\.theme, ResolvedTheme.fallbackLight)
                .environment(\.chatStyle, ChatStyle(settings: app.settings))
            return try await show(view, uiState: uiState, size: CGSize(width: 200, height: 420))
        }

        /// The middle of the row for `nick` in the member list of
        /// `buffer`, in the window, from the list's metrics: the header and
        /// filter field, then each rank's section header and rows. (SwiftUI
        /// builds no accessibility tree to find rows by until a client asks.)
        private func rowPoint(_ nick: String, of buffer: BufferModel, in hosted: Hosted) throws -> CGPoint {
            let session = try session()
            let style = ChatStyle(settings: Self.app.settings)
            let headerFont = NSFont.systemFont(ofSize: 10, weight: .semibold)
            let sectionHeight = NSLayoutManager().defaultLineHeight(for: headerFont) + 13
            let rowHeight = CGFloat(style.sidebarRowHeight)
            var y = SidebarMetrics.titleStripHeight + 8 + 24 + 4
            for group in MemberGroup.groups(for: buffer.members, prefixes: session.isupport.prefixes) {
                y += sectionHeight + 1
                for member in group.members {
                    if member.nick == nick {
                        let local = CGPoint(x: 60, y: y + rowHeight / 2)
                        let flipped = hosted.host.isFlipped ? local : CGPoint(x: local.x, y: hosted.host.bounds.height - local.y)
                        return hosted.host.convert(flipped, to: nil)
                    }
                    y += rowHeight + 1
                }
            }
            throw RowNotFound(nick: nick)
        }

        private struct RowNotFound: Error {
            let nick: String
        }

        @Test func aMemberRowOpensTheUserMenu() async throws {
            let hosted = try await hostMemberList(buffer("#vela"))
            defer { hosted.close() }
            let menu = contextMenu(at: try rowPoint("marisol", of: buffer("#vela"), in: hosted), in: hosted)
            #expect(Array(menu.items.prefix(5)) == Self.userMenuStart, "\(menu.items)")
            for item in ["Copy Nick", "Deop", "Halfop", "Voice", "Make Admin", "Kick", "Ban", "Kick + Ban", "Ignore"] {
                #expect(menu.items.contains(item), "\(item): \(menu.items)")
            }
            // Yourself: no messaging or moderation, but your own ranks.
            let own = contextMenu(at: try rowPoint("doug", of: buffer("#vela"), in: hosted), in: hosted)
            #expect(own.items.first == "Whois", "\(own.items)")
            #expect(own.items.contains("Remove Owner"), "\(own.items)")
            for item in ["Message", "Ping", "Kick", "Ban", "Ignore"] {
                #expect(!own.items.contains(item), "\(item): \(own.items)")
            }
        }

        @Test func aSelectionOfSeveralSharesOneMenu() async throws {
            let selection = MemberSelection(nicks: ["wren", "nadia", "ada"])
            let hosted = try await hostMemberList(buffer("#vela"), selection: selection)
            defer { hosted.close() }
            let menu = contextMenu(at: try rowPoint("wren", of: buffer("#vela"), in: hosted), in: hosted)
            #expect(menu.items.first == "Copy Nicks", "\(menu.items)")
            for item in ["Op", "Voice", "Devoice", "Kick", "Ban", "Kick + Ban"] {
                #expect(menu.items.contains(item), "\(item): \(menu.items)")
            }
            for item in ["Message", "Whois", "Ping", "Ignore"] {
                #expect(!menu.items.contains(item), "\(item): \(menu.items)")
            }
            // A row outside the selection gets its own menu.
            let other = contextMenu(at: try rowPoint("kenji", of: buffer("#vela"), in: hosted), in: hosted)
            #expect(Array(other.items.prefix(5)) == Self.userMenuStart, "\(other.items)")
            #expect(other.items.contains("Deop"), "\(other.items)")
            // Kick with a reason, for all of them.
            try menu.perform("Kick with Reason…")
            #expect(hosted.uiState.kickRequest?.nicks == ["ada", "nadia", "wren"])
            #expect(hosted.uiState.kickRequest?.ban == false)
        }

        @Test func commandAndShiftClicksSelectRows() async throws {
            let vela = try buffer("#vela")
            let hosted = try await hostMemberList(vela)
            defer { hosted.close() }
            // The test runner is never the active app, so AppKit only passes a
            // click on to a view that takes the first mouse.
            let accept: @convention(block) (AnyObject, NSEvent?) -> Bool = { _, _ in true }
            class_addMethod(type(of: hosted.host), #selector(NSView.acceptsFirstMouse(for:)), imp_implementationWithBlock(accept), "c@:@")

            func click(_ nick: String, _ modifiers: NSEvent.ModifierFlags = [], count: Int = 1) async throws {
                let point = try rowPoint(nick, of: vela, in: hosted)
                for clickCount in 1...count {
                    for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                        Self.eventNumber += 1
                        NSApp.sendEvent(NSEvent.mouseEvent(
                            with: type, location: point, modifierFlags: modifiers,
                            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: hosted.window.windowNumber,
                            context: nil, eventNumber: Self.eventNumber, clickCount: clickCount, pressure: type == .leftMouseUp ? 0 : 1
                        )!)
                        try await Task.sleep(for: .milliseconds(30))
                    }
                }
                // Longer than a double-click, so the next click is a new one.
                try await Task.sleep(for: .milliseconds(Int(NSEvent.doubleClickInterval * 1000) + 50))
            }

            try await click("lukas")
            try await click("priya", .shift)
            try await click("nadia", .command)
            // lukas…priya is lukas, nadia, oskar_away and priya; nadia is
            // then taken out.
            let menu = contextMenu(at: try rowPoint("priya", of: vela, in: hosted), in: hosted)
            #expect(menu.items.first == "Copy Nicks", "\(menu.items)")
            try menu.perform("Kick + Ban with Reason…")
            #expect(hosted.uiState.kickRequest?.nicks == ["lukas", "oskar_away", "priya"])
            #expect(hosted.uiState.kickRequest?.ban == true)
            // A plain click goes back to one.
            try await click("wren")
            let single = contextMenu(at: try rowPoint("priya", of: vela, in: hosted), in: hosted)
            #expect(single.items.first == "Message", "\(single.items)")
            // A double-click still opens a conversation.
            Self.app.select(vela)
            #expect(Self.app.selectedBuffer?.name == "#vela")
            try await click("theo", count: 2)
            #expect(Self.app.selectedBuffer?.name == "theo")
        }

        @Test func aRegularMemberSeesNoModerationInTheList() async throws {
            let hosted = try await hostMemberList(buffer("#vela-offtopic"))
            defer { hosted.close() }
            let menu = contextMenu(at: try rowPoint("marisol", of: buffer("#vela-offtopic"), in: hosted), in: hosted)
            #expect(Array(menu.items.prefix(5)) == Self.userMenuStart, "\(menu.items)")
            for item in ["Op", "Deop", "Voice", "Kick", "Ban"] {
                #expect(!menu.items.contains(item), "\(item): \(menu.items)")
            }
        }
    }
}

// MARK: Pure pieces

@MainActor
@Suite("Member list selection")
struct MemberSelectionTests {
    private let order = ["a", "b", "c", "d", "e"]

    @Test func aClickSelectsOne() {
        var selection = MemberSelection()
        selection.click("b", kind: .select, order: order)
        selection.click("d", kind: .select, order: order)
        #expect(selection.nicks == ["d"])
    }

    @Test func commandClicksAddAndRemove() {
        var selection = MemberSelection()
        selection.click("a", kind: .select, order: order)
        selection.click("c", kind: .toggle, order: order)
        selection.click("e", kind: .toggle, order: order)
        #expect(selection.nicks == ["a", "c", "e"])
        selection.click("c", kind: .toggle, order: order)
        #expect(selection.nicks == ["a", "e"])
    }

    @Test func shiftClicksSelectARun() {
        var selection = MemberSelection()
        selection.click("b", kind: .select, order: order)
        selection.click("d", kind: .extend, order: order)
        #expect(selection.nicks == ["b", "c", "d"])
        // From the same anchor, the other way.
        selection.click("a", kind: .extend, order: order)
        #expect(selection.nicks == ["a", "b"])
        // ⇧⌘ adds a run to what's there.
        selection.click("e", kind: .toggle, order: order)
        selection.click("d", kind: .extendAdding, order: order)
        #expect(selection.nicks == ["a", "b", "d", "e"])
    }

    @Test func peopleWhoLeaveDropOut() {
        var selection = MemberSelection(nicks: ["a", "b", "c"], anchor: "a")
        selection.keep(["b", "c", "d"])
        #expect(selection.nicks == ["b", "c"])
        #expect(selection.anchor == nil)
    }
}

@Suite("Mentioning from a menu")
struct MentionInsertionTests {
    @Test func spacedForWhereTheCaretIs() {
        #expect(ComposerInsertion.mentionText(for: "wren", before: "") == "wren: ")
        #expect(ComposerInsertion.mentionText(for: "wren", before: "thanks ") == "wren ")
        #expect(ComposerInsertion.mentionText(for: "wren", before: "thanks") == " wren ")
    }

    @MainActor
    @Test func kickSheetTitles() {
        let id = BufferID(networkID: UUID(), foldedName: "#vela")
        #expect(KickReasonSheet.title(for: KickRequest(bufferID: id, nicks: ["wren"], ban: false, reason: ""), channel: "#vela") == "Kick wren from #vela")
        #expect(KickReasonSheet.title(for: KickRequest(bufferID: id, nicks: ["a", "b"], ban: true, reason: ""), channel: "#vela") == "Kick and ban 2 people from #vela")
    }
}
