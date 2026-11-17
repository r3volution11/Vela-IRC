// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
import VelaCore

/// Intents identify buffers by `BufferID.description`.
@Suite("BufferID strings")
struct BufferIDParsingTests {
    @Test func roundTrips() {
        let id = BufferID(networkID: UUID(), foldedName: "#vela")
        #expect(BufferID(string: id.description) == id)
    }

    @Test func namesMayContainSlashes() {
        let network = UUID()
        #expect(BufferID(string: "\(network.uuidString)/#a/b")?.foldedName == "#a/b")
    }

    @Test func lowercaseUUIDsParse() {
        let network = UUID()
        #expect(BufferID(string: "\(network.uuidString.lowercased())/#vela")?.networkID == network)
    }

    @Test(arguments: ["", "#vela", "not-a-uuid/#vela", "\(UUID().uuidString)/"])
    func rejectsMalformed(_ string: String) {
        #expect(BufferID(string: string) == nil)
    }
}
