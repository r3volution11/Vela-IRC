// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import Testing
@testable import VelaCore
import VelaMedia
import VelaStore
import VelaTheme
@testable import VelaUI

extension LinkSelectionTests {
    /// The message box's emoji and GIF picker, hosted in the chat column
    /// (`ChatColumnView`) in an offscreen window, with fake GIF services
    /// (`FakeGIFServices`): opened with the smiley or ⇧⌘E, driven with key
    /// events, and counted, request by request.
    ///
    /// Nested in the serialized `LinkSelectionTests` with the other suites
    /// that send events to offscreen windows.
    @MainActor
    @Suite("Emoji and GIF picker", .serialized)
    struct ComposerPickerTests {
        private func host(gifs: FakeGIFServices = FakeGIFServices(), tab: ComposerPickerTab = .emoji, configure: (AppModel) -> Void = { _ in }) async throws -> PickerHost {
            ComposerPickerTab.remembered = tab
            let hosted = try PickerHost(gifs: gifs, configure: configure)
            try await hosted.settle(500)
            return hosted
        }

        // MARK: Opening

        @Test func theSmileyOpensAndClosesThePicker() async throws {
            let hosted = try await host()
            defer { hosted.close() }
            #expect(hosted.pickerWindow == nil)
            let smiley = try await hosted.windowPoint(of: "Emoji and GIFs")
            try await hosted.click(at: smiley)
            #expect(try await hosted.wait { hosted.searchField?.currentEditor() != nil }, "clicking the smiley didn't open the picker")
            let window = try #require(hosted.pickerWindow)
            // The search field has the focus, on the Emoji tab.
            #expect(hosted.searchField?.placeholderAttributedString?.string == "Search emoji")
            #expect(hosted.element("Emoji tab", inPicker: true) != nil)
            // Opening on the Emoji tab asks no GIF service anything.
            #expect(hosted.gifs.transport.requests.isEmpty)
            #expect(hosted.gifs.countMade() == 0)
            // Clicked again, it closes.
            try await hosted.click(at: smiley)
            #expect(try await hosted.wait { !window.isVisible }, "the picker didn't close")
        }

        @Test func shiftCommandEOpensAndClosesThePicker() async throws {
            let hosted = try await host()
            defer { hosted.close() }
            let command = VelaCommandCatalog.emojiAndGIFs(settings: hosted.app.settings, uiState: hosted.uiState, hasBuffer: true)
            #expect(command.shortcut == VelaCommandCatalog.Shortcuts.emojiAndGIFs)
            #expect(ShortcutGlyphs.string(for: VelaCommandCatalog.Shortcuts.emojiAndGIFs) == "⇧⌘E")
            #expect(command.paletteTitle == "Message Box: Emoji & GIFs…")
            command.perform()
            #expect(try await hosted.wait { hosted.searchField?.currentEditor() != nil }, "⇧⌘E didn't open the picker")
            let window = try #require(hosted.pickerWindow)
            command.perform()
            #expect(try await hosted.wait { !window.isVisible }, "⇧⌘E didn't close the picker")
            // Without GIFs it's just emoji.
            hosted.app.settings[.gifsEnabled] = false
            #expect(VelaCommandCatalog.emojiAndGIFs(settings: hosted.app.settings, uiState: hosted.uiState, hasBuffer: true).title == "Emoji…")
            #expect(!VelaCommandCatalog.emojiAndGIFs(settings: hosted.app.settings, uiState: hosted.uiState, hasBuffer: false).isEnabled)
        }

        // MARK: Emoji

        @Test func searchingAndPickingAnEmojiInsertsItAtTheCaret() async throws {
            let recents = UserDefaults.standard.stringArray(forKey: "Vela.recentEmoji")
            defer { UserDefaults.standard.set(recents, forKey: "Vela.recentEmoji") }
            let hosted = try await host()
            defer { hosted.close() }
            let composer = try #require(hosted.composer)
            hosted.window.makeFirstResponder(composer)
            composer.insertText("hello world", replacementRange: composer.selectedRange())
            composer.setSelectedRange(NSRange(location: 5, length: 0))
            try await hosted.openPicker()
            let picker = try #require(hosted.pickerWindow)
            try await hosted.typeInPicker("tada")
            try await hosted.settle()
            #expect(hosted.element("Party Popper", inPicker: true) != nil, "no 🎉 in the results")
            try await hosted.press(.down, in: picker)
            try await hosted.press(.returnKey, in: picker, settling: 400)
            #expect(try await hosted.wait { !picker.isVisible }, "picking didn't close the picker")
            #expect(try await hosted.wait { composer.string == "hello🎉 world" }, "\(composer.string)")
            // The message box has the focus back, the caret after the emoji.
            #expect(hosted.window.firstResponder === composer)
            #expect(composer.selectedRange().location == ("hello🎉" as NSString).length)
            #expect(EmojiRecents.recent.first == "🎉")
        }

        @Test func arrowsMoveAndEscClosesBackToTheMessageBox() async throws {
            let hosted = try await host()
            defer { hosted.close() }
            let composer = try #require(hosted.composer)
            try await hosted.openPicker()
            let picker = try #require(hosted.pickerWindow)
            // Recents first: ↓ selects the first, → the next, ↓ a row down.
            try await hosted.press(.down, in: picker)
            try await hosted.press(.right, in: picker)
            try await hosted.press(.down, in: picker)
            try await hosted.press(.left, in: picker)
            try await hosted.press(.up, in: picker)
            try await hosted.press(.returnKey, in: picker, settling: 400)
            // The first recent emoji: down, right, down, left, up.
            let first = EmojiRecents.frequent().first ?? ""
            #expect(try await hosted.wait { composer.string == first }, "\(composer.string) instead of \(first)")
            try await hosted.openPicker()
            let again = try #require(hosted.pickerWindow)
            try await hosted.press(.escape, in: again, settling: 300)
            #expect(try await hosted.wait { !again.isVisible }, "Esc didn't close the picker")
            #expect(try await hosted.wait { hosted.window.firstResponder === composer })
            #expect(composer.string == first)
        }

        /// The reaction picker shares the grid: search, Return, and its pick.
        @Test func theReactionPickerStillPicks() async throws {
            var picked: [String] = []
            let view = EmojiPickerView { picked.append($0) }
                .environment(\.theme, ResolvedTheme.fallbackLight)
            let host = NSHostingView(rootView: view)
            let window = NSWindow(contentRect: CGRect(x: -9000, y: -9000, width: 400, height: 420), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.orderFrontRegardless()
            defer {
                window.orderOut(nil)
                window.contentView = nil
            }
            try await Task.sleep(for: .milliseconds(300))
            let field = try #require(PickerHost.findAll(in: host) { $0 is PaletteTextField }.first as? PaletteTextField)
            let editor = try #require(field.currentEditor() as? NSTextView, "the search field doesn't have the focus")
            editor.insertText("thumbs up", replacementRange: editor.selectedRange())
            try await Task.sleep(for: .milliseconds(150))
            editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
            #expect(picked == ["👍"])
            // The arrows pick too: the first frequent one, then the one after it.
            editor.selectAll(nil)
            editor.insertText("", replacementRange: editor.selectedRange())
            try await Task.sleep(for: .milliseconds(150))
            editor.doCommand(by: #selector(NSResponder.moveDown(_:)))
            editor.doCommand(by: #selector(NSResponder.moveRight(_:)))
            try await Task.sleep(for: .milliseconds(100))
            editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
            #expect(picked.count == 2)
            #expect(picked.last == EmojiRecents.frequent().dropFirst().first)
        }

        // MARK: GIFs

        private func waitForResults(_ hosted: PickerHost, prefix: String) async throws {
            #expect(try await hosted.wait { hosted.element(prefix, prefix: true, inPicker: true) != nil }, "no result starting \(prefix)")
            try await hosted.settle()
        }

        @Test func tabSwitchesToGIFsAndTrendingIsAskedOncePerSession() async throws {
            let hosted = try await host()
            defer { hosted.close() }
            try await hosted.openPicker()
            let picker = try #require(hosted.pickerWindow)
            try await hosted.press(.tab, in: picker)
            #expect(hosted.searchField?.placeholderAttributedString?.string == "Search Fakey")
            try await waitForResults(hosted, prefix: "Trending 100, by @maker")
            #expect(hosted.gifs.transport.trendingRequests.count == 1)
            // The attribution, always in view under the grid.
            #expect(hosted.element("Powered by Fakey", inPicker: true) != nil)
            // ⌃Tab goes back to Emoji and on to GIFs again.
            try await hosted.press(.controlTab, in: picker)
            #expect(hosted.searchField?.placeholderAttributedString?.string == "Search emoji")
            try await hosted.press(.controlTab, in: picker)
            #expect(hosted.searchField?.placeholderAttributedString?.string == "Search Fakey")
            try await waitForResults(hosted, prefix: "Trending 100")
            // View on Fakey: what's trending, on the service's site.
            try await hosted.press("View on Fakey", inPicker: true)
            #expect(hosted.opened.urls == [URL(string: "https://gifs.test/site/trending")!])
            // Closed and opened again (on GIFs, the tab used last): from memory.
            try await hosted.press(.escape, in: picker, settling: 300)
            #expect(ComposerPickerTab.remembered == .gifs)
            try await hosted.openPicker()
            try await waitForResults(hosted, prefix: "Trending 100")
            #expect(hosted.gifs.transport.trendingRequests.count == 1)
            #expect(hosted.gifs.transport.searchRequests.isEmpty)
        }

        @Test func typingQuicklySearchesOnce() async throws {
            let hosted = try await host(tab: .gifs)
            defer { hosted.close() }
            try await hosted.openPicker()
            let picker = try #require(hosted.pickerWindow)
            try await waitForResults(hosted, prefix: "Trending 100")
            // One character is too short to search.
            try await hosted.typeInPicker("c")
            try await Task.sleep(for: .milliseconds(600))
            #expect(hosted.gifs.transport.searchRequests.isEmpty)
            try await hosted.typeInPicker("ats & dogs")
            try await waitForResults(hosted, prefix: "Cats & Dogs 100")
            let searches = hosted.gifs.transport.searchRequests
            #expect(searches.count == 1, "\(searches)")
            #expect(searches.first.flatMap(hosted.gifs.transport.query(of:)) == "cats & dogs")
            // View on Fakey: this search.
            try await hosted.press("View on Fakey", inPicker: true)
            #expect(hosted.opened.urls.last == URL(string: "https://gifs.test/site/search/cats-%26-dogs")!)
            // Return sends a waiting search at once.
            let editor = try #require(hosted.searchField?.currentEditor() as? NSTextView)
            editor.selectAll(nil)
            editor.insertText("owls", replacementRange: editor.selectedRange())
            try await hosted.press(.returnKey, in: picker, settling: 60)
            #expect(hosted.gifs.transport.searchRequests.count == 2)
            try await waitForResults(hosted, prefix: "Owls 100")
            // A search made before comes from memory.
            editor.selectAll(nil)
            editor.insertText("cats & dogs", replacementRange: editor.selectedRange())
            try await waitForResults(hosted, prefix: "Cats & Dogs 100")
            try await Task.sleep(for: .milliseconds(500))
            #expect(hosted.gifs.transport.searchRequests.count == 2)
            #expect(hosted.gifs.transport.trendingRequests.count == 1)
        }

        @Test func pickingAGIFAddsAChipAndSendsItsLink() async throws {
            let hosted = try await host(tab: .gifs)
            defer { hosted.close() }
            let composer = try #require(hosted.composer)
            try await hosted.openPicker()
            let picker = try #require(hosted.pickerWindow)
            try await waitForResults(hosted, prefix: "Trending 100")
            try await hosted.press(.down, in: picker)
            try await hosted.press(.right, in: picker)
            try await hosted.press(.returnKey, in: picker, settling: 400)
            #expect(try await hosted.wait { !picker.isVisible }, "picking didn't close the picker")
            let gif = try #require(hosted.uiState.composerGIFs[hosted.buffer.id])
            #expect(gif.url.absoluteString == "https://media.test/share/trending-all-1-1.gif")
            #expect(try await hosted.wait { hosted.element("GIF: Trending 101", prefix: true) != nil }, "no chip")
            #expect(try await hosted.wait { hosted.window.firstResponder === composer })
            // Words, then Return: the words and the link, as one message.
            composer.insertText("nice", replacementRange: composer.selectedRange())
            try await hosted.press(.returnKey, in: hosted.window, settling: 300)
            #expect(InputHistoryStore.shared.entries(for: hosted.buffer.id).last == "nice https://media.test/share/trending-all-1-1.gif")
            #expect(composer.string.isEmpty)
            #expect(hosted.uiState.composerGIFs[hosted.buffer.id] == nil)
            #expect(try await hosted.wait { hosted.element("GIF: ", prefix: true) == nil }, "the chip stayed")

            // Delete before the text takes a GIF out, like a token.
            try await hosted.openPicker()
            let again = try #require(hosted.pickerWindow)
            try await waitForResults(hosted, prefix: "Trending 100")
            try await hosted.press(.down, in: again)
            try await hosted.press(.returnKey, in: again, settling: 400)
            #expect(hosted.uiState.composerGIFs[hosted.buffer.id] != nil)
            try await hosted.press(.delete, in: hosted.window)
            #expect(hosted.uiState.composerGIFs[hosted.buffer.id] == nil)

            // A GIF alone, sent with the send button.
            try await hosted.openPicker()
            let third = try #require(hosted.pickerWindow)
            try await hosted.press(.down, in: third)
            try await hosted.press(.returnKey, in: third, settling: 400)
            try await hosted.press("Send message")
            try await hosted.settle(300)
            #expect(InputHistoryStore.shared.entries(for: hosted.buffer.id).last == "https://media.test/share/trending-all-1-0.gif")
            #expect(hosted.uiState.composerGIFs[hosted.buffer.id] == nil)
        }

        @Test func scrollingToTheEndLoadsTheNextPageAndNothingSooner() async throws {
            let hosted = try await host(tab: .gifs)
            defer { hosted.close() }
            GIFMediaStandIn.loads.withLock { $0.removeAll() }
            try await hosted.openPicker()
            try await waitForResults(hosted, prefix: "Trending 100")
            try await Task.sleep(for: .milliseconds(600))
            // No prefetching: one page until the grid is scrolled.
            #expect(hosted.gifs.transport.trendingRequests.count == 1)
            // Only the cells in view load their previews (a still and an
            // animation each), not all 24.
            let loads = GIFMediaStandIn.loads.withLock { $0 }
            let animations = Set(loads.filter { $0.path().hasPrefix("/animation/") })
            #expect(!animations.isEmpty, "no previews loaded")
            #expect(animations.count < 24, "\(animations.count) animated previews loaded for 24 results")
            let picker = try #require(hosted.pickerWindow?.contentView)
            let scrollView = try #require(PickerHost.findAll(in: picker) { $0 is NSScrollView }.compactMap { $0 as? NSScrollView }.max { $0.frame.height < $1.frame.height })
            let documentHeight = scrollView.documentView?.frame.height ?? 0
            scrollView.contentView.scroll(to: CGPoint(x: 0, y: max(0, documentHeight - scrollView.contentSize.height)))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            #expect(try await hosted.wait { hosted.gifs.transport.trendingRequests.count == 2 }, "the next page didn't load")
            #expect(hosted.gifs.transport.trendingRequests.last?.query()?.contains("page=2") == true)
        }

        @Test func stillPreviewsWhenAnimationIsOff() async throws {
            let hosted = try await host(tab: .gifs) { $0.settings[.gifsAnimatePreviews] = false }
            defer { hosted.close() }
            GIFMediaStandIn.loads.withLock { $0.removeAll() }
            try await hosted.openPicker()
            try await waitForResults(hosted, prefix: "Trending 100")
            try await Task.sleep(for: .milliseconds(500))
            let loads = GIFMediaStandIn.loads.withLock { $0 }
            #expect(loads.contains { $0.path().hasPrefix("/still/") })
            #expect(!loads.contains { $0.path().hasPrefix("/animation/") })
        }

        @Test func gifsOffHidesTheTabAndAsksNothing() async throws {
            let hosted = try await host(tab: .gifs) { $0.settings[.gifsEnabled] = false }
            defer { hosted.close() }
            try await hosted.openPicker()
            let picker = try #require(hosted.pickerWindow)
            #expect(hosted.searchField?.placeholderAttributedString?.string == "Search emoji")
            #expect(hosted.element("GIFs tab", inPicker: true) == nil)
            try await hosted.press(.tab, in: picker)
            try await hosted.press(.controlTab, in: picker)
            #expect(hosted.searchField?.placeholderAttributedString?.string == "Search emoji")
            try await hosted.typeInPicker("cats")
            try await Task.sleep(for: .milliseconds(600))
            #expect(hosted.gifs.transport.requests.isEmpty)
            #expect(hosted.gifs.countMade() == 0)
        }

        // MARK: Errors

        @Test func busyIsCalmAndHoldsBack() async throws {
            let gifs = FakeGIFServices()
            gifs.transport.state.withLock { $0.status = 429 }
            let hosted = try await host(gifs: gifs, tab: .gifs)
            defer { hosted.close() }
            try await hosted.openPicker()
            #expect(try await hosted.wait { hosted.element("GIF search is busy right now", inPicker: true) != nil })
            let retry = try #require(hosted.element("Try Again", inPicker: true))
            #expect(retry.isAccessibilityEnabled?() == false, "Try Again should wait a minute")
            #expect(hosted.element(GIFMessage.ownKeyTitle, inPicker: true) != nil)
            // Typing on doesn't knock again.
            try await hosted.typeInPicker("cats")
            try await Task.sleep(for: .milliseconds(700))
            #expect(gifs.transport.requests.count == 1)
        }

        @Test func offlineOffersTryAgain() async throws {
            let gifs = FakeGIFServices()
            gifs.transport.state.withLock { $0.fails = true }
            let hosted = try await host(gifs: gifs, tab: .gifs)
            defer { hosted.close() }
            try await hosted.openPicker()
            #expect(try await hosted.wait { hosted.element("Can't reach Fakey", inPicker: true) != nil })
            gifs.transport.state.withLock { $0.fails = false }
            try await hosted.press("Try Again", inPicker: true)
            try await waitForResults(hosted, prefix: "Trending 100")
            #expect(gifs.transport.requests.count == 2)
        }

        @Test func withoutAKeyGIFsAreNotSetUp() async throws {
            let gifs = FakeGIFServices(builtInKey: nil)
            let hosted = try await host(gifs: gifs, tab: .gifs)
            defer { hosted.close() }
            try await hosted.openPicker()
            #expect(try await hosted.wait { hosted.element("GIFs aren't set up in this build", inPicker: true) != nil })
            #expect(hosted.element(GIFMessage.ownKeyTitle, inPicker: true) != nil)
            #expect(gifs.transport.requests.isEmpty)
            // Your own key fixes it.
            try gifs.services.keys.setKey("mine", for: .klipy)
            #expect(gifs.services.setup(for: .klipy).apiKey == "mine")
            #expect(gifs.services.setup(for: .klipy).usesOwnKey)
        }

        // MARK: Send button and smiley

        @Test func theSendButtonSendsLikeReturn() async throws {
            let hosted = try await host()
            defer { hosted.close() }
            let composer = try #require(hosted.composer)
            let send = try await hosted.waitForElement("Send message")
            #expect(send.isAccessibilityEnabled?() == false, "send is enabled with nothing to send")
            hosted.window.makeFirstResponder(composer)
            composer.insertText("from the button", replacementRange: composer.selectedRange())
            try await hosted.settle()
            let enabled = try await hosted.waitForElement("Send message")
            #expect(enabled.isAccessibilityEnabled?() == true)
            hosted.window.makeFirstResponder(nil)
            try await hosted.press("Send message")
            try await hosted.settle(300)
            #expect(InputHistoryStore.shared.entries(for: hosted.buffer.id).last == "from the button")
            #expect(composer.string.isEmpty)
            #expect(try await hosted.wait { hosted.window.firstResponder === composer }, "the message box didn't get the focus back")
        }

        @Test func theButtonsFollowTheSettingAndTheConnection() async throws {
            let hosted = try await host()
            defer { hosted.close() }
            #expect(try await hosted.shows("Send message"))
            #expect(try await hosted.shows("Emoji and GIFs"))
            hosted.app.settings[.inputShowSendButton] = false
            try await hosted.settle()
            #expect(try await hosted.hides("Send message"))
            #expect(try await hosted.shows("Emoji and GIFs"))
            hosted.app.settings[.inputShowSendButton] = true
            // Not in the channel: Join instead of send; emoji still go in.
            hosted.buffer.isJoined = false
            try await hosted.settle()
            #expect(try await hosted.shows("Join"))
            #expect(try await hosted.hides("Send message"))
            #expect(try await hosted.shows("Emoji and GIFs"))
            hosted.buffer.isJoined = true
            // Offline: Reconnect.
            hosted.session.connectionState = .disconnected
            try await hosted.settle()
            #expect(try await hosted.shows("Reconnect"))
            #expect(try await hosted.hides("Send message"))
            #expect(try await hosted.shows("Emoji and GIFs"))
            hosted.session.connectionState = .connected
            try await hosted.settle()
            #expect(try await hosted.shows("Send message"))
        }

        /// The smiley and send button sit centered on the first line, inside
        /// the field, whatever the text size and border, and stay there as
        /// the text grows.
        @Test(arguments: [9.0, 13.0, 28.0])
        func theButtonsSitOnTheFirstLine(fontSize: Double) async throws {
            for border in MessageBoxBorder.allCases {
                let hosted = try await host {
                    $0.settings[.chatFontSize] = fontSize
                    $0.settings[.appearanceMessageBoxBorder] = border
                }
                defer { hosted.close() }
                let composer = try #require(hosted.composer)
                let editor = try #require(composer.enclosingScrollView)
                func screenFrame(_ view: NSView) -> CGRect {
                    hosted.window.convertToScreen(view.convert(view.bounds, to: nil))
                }
                func check(_ label: String, lines: Int) async throws {
                    let element = try await hosted.waitForElement(label)
                    let frame = try #require(element.accessibilityFrame?())
                    let field = screenFrame(editor)
                    let firstLine = InputBar.singleLineHeight(for: composer.font ?? .systemFont(ofSize: fontSize))
                    // Screen coordinates go up: the first line is at the top.
                    let firstLineMidY = field.maxY - firstLine / 2
                    #expect(abs(frame.midY - firstLineMidY) <= 1.5, "\(label) at \(frame.midY), first line at \(firstLineMidY), \(lines) lines, size \(fontSize), \(border)")
                    #expect(frame.minX >= field.maxX - 0.5, "\(label) overlaps the text (\(border), \(fontSize))")
                    #expect(frame.width >= 22 && frame.height >= 22, "\(label) is \(frame.size)")
                }
                try await check("Emoji and GIFs", lines: 1)
                try await check("Send message", lines: 1)
                hosted.window.makeFirstResponder(composer)
                composer.insertText("one\ntwo\nthree", replacementRange: composer.selectedRange())
                try await hosted.settle(300)
                try await check("Emoji and GIFs", lines: 3)
                try await check("Send message", lines: 3)
            }
        }
    }
}

// MARK: - Pieces

@MainActor
@Suite("Emoji and GIF picker pieces")
struct ComposerPickerPieceTests {
    @Test func arrowsMoveThroughSectionsByRows() throws {
        let content = EmojiGridContent(query: "", frequent: ["😀", "😃", "😄"], columns: 9)
        let frequent = content.sections[0].items
        // Nothing selected: any arrow selects the first.
        #expect(content.moved(from: nil, .right) == frequent[0])
        #expect(content.moved(from: frequent[0], .right) == frequent[1])
        // From the end of a section into the next, and back.
        let firstSmiley = content.sections[1].items[0]
        #expect(content.moved(from: frequent[2], .right) == firstSmiley)
        #expect(content.moved(from: firstSmiley, .left) == frequent[2])
        // Down from a short section keeps the column in the next.
        #expect(content.moved(from: frequent[1], .down) == content.sections[1].items[1])
        // Up from the next section's first row lands in the last row above.
        #expect(content.moved(from: content.sections[1].items[2], .up) == frequent[2])
        #expect(content.moved(from: content.sections[1].items[0], .up) == frequent[0])
        // Rows within a section.
        #expect(content.moved(from: content.sections[1].items[0], .down) == content.sections[1].items[9])
        // Nowhere to go: stays.
        #expect(content.moved(from: frequent[0], .up) == frequent[0])
        #expect(content.moved(from: frequent[0], .left) == frequent[0])
        // Searching: one section of results.
        let search = EmojiGridContent(query: "heart", frequent: [], columns: 9)
        #expect(search.isSearching)
        #expect(search.sections.map(\.id) == ["results"])
        #expect(EmojiGridContent(query: "zzzzqq", frequent: [], columns: 9).isEmpty)
    }

    /// The pickers search the `:shortcode:` names too, as completion knows them.
    @Test func emojiSearchKnowsShortcodes() {
        #expect(EmojiCatalog.search("heart_eyes").first == "😍")
        #expect(EmojiCatalog.search("ok_hand").contains("👌"))
        #expect(EmojiCatalog.search("sweat smile").contains("😅"))
        #expect(EmojiCatalog.search("+1").first == "👍")
    }

    @Test func theMessageCarriesTheGIFAfterTheText() throws {
        let result = GIFSearchResult(id: "x", title: "Hi", stills: [], animations: [], shareURL: URL(string: "https://static.klipy.com/a.gif")!)
        let gif = ComposerGIF(result: result, provider: KLIPYProvider())
        #expect(ComposerGIF.message(text: "", gif: gif) == "https://static.klipy.com/a.gif")
        #expect(ComposerGIF.message(text: "  \n", gif: gif) == "https://static.klipy.com/a.gif")
        #expect(ComposerGIF.message(text: "look ", gif: gif) == "look https://static.klipy.com/a.gif")
        #expect(ComposerGIF.message(text: "/me waves", gif: gif) == "/me waves https://static.klipy.com/a.gif")
        #expect(ComposerGIF.message(text: "plain", gif: nil) == "plain")
        #expect(gif.serviceName == "KLIPY")
    }

    /// Keys typed in Settings go to the Keychain, never settings.json.
    @Test func ownKeysGoToTheKeychain() throws {
        let keychain = Keychain.inMemory()
        let keys = GIFKeyStore(keychain: keychain)
        #expect(keys.key(for: .klipy) == nil)
        try keys.setKey("  mine-123 \n", for: .klipy)
        #expect(keychain.secret(account: "gifs/klipy") == "mine-123")
        #expect(keys.key(for: .klipy) == "mine-123")
        try keys.setKey("   ", for: .klipy)
        #expect(keychain.secret(account: "gifs/klipy") == nil)
        #expect(keys.key(for: .klipy) == nil)
        // Your own key wins over the built-in one; without one, GIPHY can't search.
        let services = GIFSearchServices(keys: keys, builtInKLIPYKey: "vela")
        #expect(services.setup(for: .klipy).apiKey == "vela")
        #expect(!services.setup(for: .klipy).usesOwnKey)
        #expect(services.setup(for: .giphy).problem == .needsOwnKey)
        try keys.setKey("g-key", for: .giphy)
        #expect(services.setup(for: .giphy).apiKey == "g-key")
        #expect(services.setup(for: .giphy).provider.id == .giphy)
    }

    @Test func theBuiltInKeyComesFromInfoPlist() {
        #expect(BuiltInGIFKeys.klipy(from: "abc123") == "abc123")
        #expect(BuiltInGIFKeys.klipy(from: " abc123\n") == "abc123")
        #expect(BuiltInGIFKeys.klipy(from: "") == nil)
        #expect(BuiltInGIFKeys.klipy(from: "$(VELA_KLIPY_API_KEY)") == nil)
        #expect(BuiltInGIFKeys.klipy(from: nil) == nil)
        #expect(BuiltInGIFKeys.klipy(from: 42) == nil)
        // The test runner has none.
        #expect(BuiltInGIFKeys.klipy() == nil)
    }

    @Test func messagesOfferTheWayForward() {
        let builtIn = GIFSearchSetup(service: .klipy, provider: KLIPYProvider(), apiKey: "vela", usesOwnKey: false)
        let own = GIFSearchSetup(service: .klipy, provider: KLIPYProvider(), apiKey: "mine", usesOwnKey: true)
        let busy = GIFMessage(error: .rateLimited, setup: builtIn)
        #expect(busy.title == "GIF search is busy right now")
        #expect(busy.message == "Try again in a few minutes, or use your own free KLIPY key.")
        #expect(busy.offersRetry)
        #expect(busy.settingsTitle == GIFMessage.ownKeyTitle)
        #expect(GIFMessage(error: .rateLimited, setup: own).settingsTitle == nil)
        let refused = GIFMessage(error: .invalidKey, setup: builtIn)
        #expect(refused.title == "KLIPY didn't accept Vela's key")
        #expect(refused.settingsTitle == GIFMessage.ownKeyTitle)
        #expect(GIFMessage(error: .invalidKey, setup: own).title == "KLIPY didn't accept your key")
        let offline = GIFMessage(error: .offline, setup: builtIn)
        #expect(offline.title == "Can't reach KLIPY")
        #expect(offline.offersRetry && offline.settingsTitle == nil)
        #expect(GIFMessage(error: .server(502), setup: builtIn).message?.contains("502") == true)
        #expect(GIFMessage(problem: .noBuiltInKey).title == "GIFs aren't set up in this build")
        #expect(GIFMessage(problem: .needsOwnKey).title == "GIPHY needs your own key")
        let giphy = GIFSearchSetup(service: .giphy, provider: GIPHYProvider(), apiKey: nil, usesOwnKey: false)
        #expect(giphy.problem == .needsOwnKey)
        #expect(GIFSearchSetup(service: .klipy, provider: KLIPYProvider(), apiKey: nil, usesOwnKey: false).problem == .noBuiltInKey)
    }

    /// The attribution strip names each service, with its site link.
    @Test(arguments: [GIFSearchServiceID.klipy, .giphy])
    func theAttributionNamesTheService(_ id: GIFSearchServiceID) async throws {
        let provider: any GIFSearchProvider = id == .klipy ? KLIPYProvider() : GIPHYProvider()
        var opened = 0
        let view = GIFAttributionBar(provider: provider) { opened += 1 }
            .frame(width: 360)
            .environment(\.theme, ResolvedTheme.fallbackLight)
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: CGRect(x: -9000, y: -9000, width: 360, height: 40), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFrontRegardless()
        let enhanced = NSSelectorFromString("accessibilitySetEnhancedUserInterfaceAttribute:")
        NSApp.perform(enhanced, with: NSNumber(value: true))
        defer {
            NSApp.perform(enhanced, with: NSNumber(value: false))
            window.orderOut(nil)
            window.contentView = nil
        }
        let name = id == .klipy ? "KLIPY" : "GIPHY"
        for _ in 0..<40 where PickerHost.element(labeled: "View on \(name)", in: host) == nil {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(PickerHost.element(labeled: "Powered by \(name)", in: host) != nil)
        let link = try #require(PickerHost.element(labeled: "View on \(name)", in: host))
        _ = link.accessibilityPerformPress?()
        #expect(opened == 1)
    }
}
