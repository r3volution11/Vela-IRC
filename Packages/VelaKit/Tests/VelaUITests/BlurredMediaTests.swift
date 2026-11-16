// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreGraphics
import Foundation
import Testing
import VelaCore
import VelaMedia
import VelaStore
@testable import VelaUI

@MainActor
@Suite("Blurred media")
struct BlurredMediaTests {
    let line = UUID()
    let image = EmbedLink(url: URL(string: "https://upload.wikimedia.org/wikipedia/commons/a/a1/Nebula.jpg")!)

    private func context(blur: Bool) -> VelaMedia.PreviewContext {
        VelaMedia.PreviewContext(blurImages: blur)
    }

    private func blur(_ store: EmbedLineStore, _ link: EmbedLink, preview: LinkPreview? = nil, blur: Bool) -> EmbedBlur {
        let context = context(blur: blur)
        let decision = store.decision(for: link, in: line, preview: preview, fetchBlock: nil, context: context)
        return store.blur(for: link, in: line, decision: decision, preview: preview, fetchBlock: nil, context: context)
    }

    @Test func blurredUntilRevealedThenOffersBlurAgain() {
        let store = EmbedLineStore()
        let blurred = blur(store, image, blur: true)
        #expect(blurred.isBlurred)
        #expect(!blurred.canBlurAgain)
        #expect(blurred.target == EmbedBlur.Target(lineID: line, linkID: image.id, linkURL: image.url))

        blurred.reveal(in: store)
        #expect(store.overrides(lineID: line, linkID: image.id).revealed)
        let revealed = blur(store, image, blur: true)
        #expect(!revealed.isBlurred)
        #expect(revealed.canBlurAgain)

        revealed.blurAgain(in: store)
        #expect(blur(store, image, blur: true).isBlurred)
    }

    @Test func nothingToBlurWhereBlurIsOff() {
        let store = EmbedLineStore()
        store.setRevealed(true, lineID: line, linkID: image.id)
        let state = blur(store, image, blur: false)
        #expect(!state.isBlurred)
        // Revealed earlier, but this buffer doesn't blur: no "Blur Again".
        #expect(!state.canBlurAgain)
    }

    @Test func cardsWithoutAnImageAreNeverBlurred() {
        let store = EmbedLineStore()
        let page = EmbedLink(url: URL(string: "https://www.swift.org/blog/")!)
        let plain = LinkPreview(url: page.url, kind: .page, title: "Swift Blog")
        #expect(!blur(store, page, preview: plain, blur: true).isBlurred)
        store.setRevealed(true, lineID: line, linkID: page.id)
        #expect(!blur(store, page, preview: plain, blur: true).canBlurAgain)

        let pictured = LinkPreview(
            url: page.url, kind: .page, title: "Swift Blog", imageURL: URL(string: "https://www.swift.org/og.png")
        )
        #expect(blur(store, page, preview: pictured, blur: true).canBlurAgain)
    }

    @Test func hidePreviewsCollapsesTheLine() {
        let store = EmbedLineStore()
        blur(store, image, blur: true).hidePreviews(in: store)
        #expect(store.isCollapsed(line))
        // Outside a link preview there's nothing to act on.
        EmbedBlur().reveal(in: store)
        EmbedBlur().hidePreviews(in: store)
        #expect(!store.isCollapsed(UUID()))
    }

    @Test func shrinksPostersToAFewPixels() async throws {
        let poster = try #require(Self.image(width: 1280, height: 720))
        let tiny = try #require(await BlurredMedia.shrink(poster))
        #expect(tiny.width == BlurredMedia.pixelSize)
        #expect(tiny.height == 14)

        let small = try #require(Self.image(width: 10, height: 20))
        #expect(await BlurredMedia.shrink(small) === small)

        // What's drawn: the few pixels scaled up smoothly, same shape.
        let standIn = try #require(await BlurredMedia.standIn(for: poster))
        #expect(standIn.width == BlurredMedia.softenedSize)
        #expect(standIn.height == 56)
    }

    @Test func blurredChannelsRowCountsChannelsAndNetworks() {
        let network = UUID().uuidString
        #expect(MediaPane.blurredTitle(["\(network)/#vela"]) == "Blurred in 1 channel")
        #expect(MediaPane.blurredTitle(["\(network)/#vela", "\(network)/#swift"]) == "Blurred in 2 channels")
        #expect(MediaPane.blurredTitle(["\(network)/*"]) == "Blurred in 1 network")
        #expect(MediaPane.blurredTitle(["\(network)/#vela", "\(network)/*", "\(UUID().uuidString)/*"])
            == "Blurred in 1 channel and 2 networks")
    }

    private static func image(width: Int, height: Int) -> CGImage? {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        return context?.makeImage()
    }
}

@MainActor
@Suite("Blur commands")
struct BlurCommandTests {
    private func makeSettings() -> SettingsStore {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "VelaUITests-\(UUID().uuidString)", directoryHint: .isDirectory)
            .appending(path: "settings.json")
        return SettingsStore(fileURL: url, watchForChanges: false)
    }

    @Test func blurEverywhereTogglesTheSetting() throws {
        let settings = makeSettings()
        let command = try #require(VelaCommandCatalog.mediaCommands(settings).first { $0.id == "media.toggleBlur" })
        #expect(command.paletteTitle == "Media: Blur Images Until Clicked")
        #expect(command.isChecked == false)
        command.perform()
        #expect(settings[.mediaBlurImages])
        let rebuilt = VelaCommandCatalog.mediaCommands(settings).first { $0.id == "media.toggleBlur" }
        #expect(rebuilt?.isChecked == true)
    }

    @Test func paletteFindsBlurByKeyword() throws {
        let items = PaletteSource.commandItems(VelaCommandCatalog.mediaCommands(makeSettings()), history: [])
        for query in ["blur", "spoiler"] {
            let first = try #require(PaletteRanker.rows(for: items, query: query, list: .commands).first)
            #expect(first.id == "media.toggleBlur", "query \(query)")
        }
    }

    @Test func bufferCommandTogglesThatBuffer() {
        let app = AppModel.demo()
        let network = UUID()
        let channel = BufferID(networkID: network, foldedName: "#vela")
        let command = VelaCommandCatalog.blurCommand(app: app, bufferID: channel)
        #expect(command.id == "buffer.toggleBlur")
        #expect(command.paletteTitle == "Buffer: Blur Images")
        #expect(command.isChecked == false)
        #expect(command.isEnabled)

        command.perform()
        #expect(app.isBlurred(for: channel))
        #expect(!app.isBlurred(for: BufferID(networkID: network, foldedName: "#other")))
        let checked = VelaCommandCatalog.blurCommand(app: app, bufferID: channel)
        #expect(checked.isChecked == true)
        checked.perform()
        #expect(!app.isBlurred(for: channel))
        #expect(app.settings[.mediaBlurredBuffers].isEmpty)
    }

    @Test func bufferCommandIsCheckedAndDisabledWhileAWiderSettingBlurs() {
        let app = AppModel.demo()
        let network = UUID()
        let channel = BufferID(networkID: network, foldedName: "#vela")

        app.setBlurred(true, forNetwork: network)
        let byNetwork = VelaCommandCatalog.blurCommand(app: app, bufferID: channel)
        #expect(byNetwork.isChecked == true)
        #expect(!byNetwork.isEnabled)
        app.setBlurred(false, forNetwork: network)

        app.settings[.mediaBlurImages] = true
        let everywhere = VelaCommandCatalog.blurCommand(app: app, bufferID: channel)
        #expect(everywhere.isChecked == true)
        #expect(!everywhere.isEnabled)
        let networkCommand = VelaCommandCatalog.networkBlurCommand(app: app, networkID: network)
        #expect(networkCommand.isChecked == true)
        #expect(!networkCommand.isEnabled)
    }

    @Test func networkCommandTogglesTheNetwork() {
        let app = AppModel.demo()
        let network = UUID()
        let command = VelaCommandCatalog.networkBlurCommand(app: app, networkID: network)
        #expect(command.resolvedMenuTitle == "Blur Images on This Network")
        #expect(!command.showsInPalette)
        #expect(command.isChecked == false)
        command.perform()
        #expect(app.isBlurred(forNetwork: network))
        #expect(app.isBlurred(for: BufferID(networkID: network, foldedName: "#any")))
        VelaCommandCatalog.networkBlurCommand(app: app, networkID: network).perform()
        #expect(!app.isBlurred(forNetwork: network))
    }
}
