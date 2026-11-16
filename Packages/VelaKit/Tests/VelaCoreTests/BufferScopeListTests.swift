// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaCore

@Suite("Buffer scope lists")
struct BufferScopeListTests {
    private let libera = UUID()
    private let oftc = UUID()

    private func buffer(_ name: String, on network: UUID) -> BufferID {
        BufferID(networkID: network, foldedName: name)
    }

    @Test func matchesSingleBuffers() {
        let list = BufferScopeList(["\(libera.uuidString)/#vela"])
        #expect(list.contains(buffer("#vela", on: libera)))
        #expect(!list.contains(buffer("#swift", on: libera)))
        #expect(!list.contains(buffer("#vela", on: oftc)))
        #expect(!list.containsNetwork(libera))
    }

    @Test func networkEntryCoversEveryBuffer() {
        let list = BufferScopeList([BufferScopeList.networkEntry(for: libera)])
        #expect(BufferScopeList.networkEntry(for: libera) == "\(libera.uuidString)/*")
        #expect(list.contains(buffer("#vela", on: libera)))
        #expect(list.contains(buffer(BufferID.serverBufferName, on: libera)))
        #expect(list.containsNetwork(libera))
        #expect(!list.contains(buffer("#vela", on: oftc)))
        #expect(!list.containsNetwork(oftc))
    }

    @Test func toleratesHandWrittenEntries() {
        let list = BufferScopeList([
            "\(libera.uuidString.lowercased())/*",
            "\(oftc.uuidString.lowercased())/#a/b",
            "not-a-uuid/*",
            "",
            "*",
        ])
        #expect(list.containsNetwork(libera))
        #expect(list.contains(buffer("#a/b", on: oftc)))
        #expect(!list.contains(buffer("#a", on: oftc)))
        #expect(!list.containsNetwork(oftc))
    }

    @Test func togglingABufferLeavesItsNetworkAlone() {
        let vela = buffer("#vela", on: libera)
        var list = BufferScopeList([BufferScopeList.networkEntry(for: oftc)])

        list.set(true, for: vela)
        list.set(true, for: vela)
        #expect(list.entries == [BufferScopeList.networkEntry(for: oftc), vela.description])
        #expect(list.contains(vela))
        #expect(!list.containsNetwork(libera))

        list.set(false, for: vela)
        #expect(list.entries == [BufferScopeList.networkEntry(for: oftc)])
        #expect(!list.contains(vela))

        // Unlisting a buffer doesn't override its listed network.
        list.set(true, forNetwork: libera)
        list.set(false, for: vela)
        #expect(list.contains(vela))
    }

    @Test func togglingANetworkKeepsBufferEntries() {
        let vela = buffer("#vela", on: libera)
        var list = BufferScopeList([vela.description])

        list.set(true, forNetwork: libera)
        list.set(true, forNetwork: libera)
        #expect(list.entries == [vela.description, "\(libera.uuidString)/*"])
        #expect(list.contains(buffer("#swift", on: libera)))

        list.set(false, forNetwork: libera)
        #expect(list.entries == [vela.description])
        #expect(!list.contains(buffer("#swift", on: libera)))
        #expect(list.contains(vela))
    }

    @Test func unlistingRemovesEquivalentHandWrittenEntries() {
        let vela = buffer("#vela", on: libera)
        var list = BufferScopeList([
            "\(libera.uuidString.lowercased())/#vela",
            "\(libera.uuidString.lowercased())/*",
            "garbage",
        ])
        list.set(false, for: vela)
        list.set(false, forNetwork: libera)
        #expect(list.entries == ["garbage"])
    }
}
