// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Testing
@testable import VelaCore

/// ⇧⌘[ / ⇧⌘] (and ⌃⇧Tab / ⌃Tab) step through the network's tabs; ⌃⌘[ /
/// ⌃⌘] step through networks, back to where you were on each.
@MainActor
@Suite("Keyboard navigation")
struct KeyboardNavigationTests {
    @Test func tabsStayInTheNetworkAndWrap() throws {
        let app = AppModel.demo()
        let libera = try #require(app.sessions.first)
        let tabs = libera.allBuffers
        #expect(tabs.count > 2)
        app.select(try #require(tabs.last))

        app.selectAdjacentTab(forward: true)
        #expect(app.selectedBufferID == libera.serverBuffer.id, "after the last tab comes the console")
        app.selectAdjacentTab(forward: true)
        #expect(app.selectedBufferID == tabs[1].id)
        app.selectAdjacentTab(forward: false)
        app.selectAdjacentTab(forward: false)
        #expect(app.selectedBufferID == tabs.last?.id, "before the console comes the last tab")

        // Every step stays on the network.
        for _ in 0..<(tabs.count * 2) {
            app.selectAdjacentTab(forward: true)
            #expect(app.selectedBufferID?.networkID == libera.id)
        }
    }

    @Test func networksReturnToWhereYouWere() throws {
        let app = AppModel.demo()
        #expect(app.sessions.count >= 2)
        let libera = app.sessions[0]
        let oftc = app.sessions[1]
        let liberaChannel = try #require(libera.channels.dropFirst().first)
        app.select(liberaChannel)

        // Never visited: its console.
        app.selectAdjacentNetwork(forward: true)
        #expect(app.selectedBufferID == oftc.serverBuffer.id)
        let oftcChannel = try #require(oftc.channels.first)
        app.select(oftcChannel)

        // Around the end and back to the start, on the channel you left.
        for _ in 1..<app.sessions.count { app.selectAdjacentNetwork(forward: true) }
        #expect(app.selectedBufferID == liberaChannel.id)
        app.selectAdjacentNetwork(forward: false)
        #expect(app.selectedBufferID?.networkID == app.sessions.last?.id)
        if app.sessions.count == 2 { #expect(app.selectedBufferID == oftcChannel.id) }
    }

    @Test func aClosedBufferIsntReturnedTo() throws {
        let app = AppModel.demo()
        let libera = try #require(app.sessions.first)
        let query = libera.ensureBuffer(name: "someone", kind: .query, persist: false)
        app.select(query)
        app.selectAdjacentNetwork(forward: true)
        libera.close(query)
        #expect(app.lastSelectedBuffer(in: libera).id == libera.serverBuffer.id)
    }
}
