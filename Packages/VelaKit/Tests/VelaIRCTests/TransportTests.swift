// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaIRC

@Suite struct LineFramerTests {
    @Test func splitsOnLFAndStripsCR() throws {
        var framer = LineFramer()
        #expect(try framer.append(Array("PING :a\r\nPING :b\nPAR".utf8)) == ["PING :a", "PING :b"])
        #expect(try framer.append(Array("TIAL\r".utf8)) == [])
        #expect(try framer.append(Array("\n\r\n\n".utf8)) == ["PARTIAL"])
        #expect(framer.flush() == nil)
    }

    @Test func handlesSplitMultibyteSequences() throws {
        var framer = LineFramer()
        let bytes = Array("héllo 😀\r\n".utf8)
        var lines: [String] = []
        for byte in bytes { lines += try framer.append([byte]) }
        #expect(lines == ["héllo 😀"])
    }

    @Test func fallsBackToLatin1PerLine() throws {
        var framer = LineFramer()
        // 0xE9 alone is invalid UTF-8 → ISO-8859-1 "é"; the next line is UTF-8.
        let lines = try framer.append([0x63, 0x61, 0x66, 0xE9, 0x0D, 0x0A] + Array("café\r\n".utf8))
        #expect(lines == ["café", "café"])
    }

    @Test func flushReturnsUnterminatedTail() throws {
        var framer = LineFramer()
        _ = try framer.append(Array("ERROR :bye\r".utf8))
        #expect(framer.flush() == "ERROR :bye")
    }

    @Test func rejectsRunawayLines() {
        var framer = LineFramer()
        #expect(throws: IRCTransportError.lineTooLong) {
            _ = try framer.append([UInt8](repeating: 0x61, count: LineFramer.maximumLineLength + 1))
        }
    }
}

@Suite struct MockTransportTests {
    @Test func deliversInjectedLinesInOrder() async throws {
        let mock = MockTransport()
        mock.receive("before open")
        let stream = try await mock.open()
        mock.receive(lines: ["one", "two"])
        mock.finish()
        var received: [String] = []
        for try await line in stream { received.append(line) }
        #expect(received == ["before open", "one", "two"])
    }

    @Test func recordsAndAwaitsSentLines() async throws {
        let mock = MockTransport()
        _ = try await mock.open()
        try await mock.send("NICK a")
        #expect(await mock.nextSentLine() == "NICK a")
        async let next = mock.nextSentLine()
        try await mock.send("USER a 0 * a")
        #expect(await next == "USER a 0 * a")
        #expect(mock.sentLines == ["NICK a", "USER a 0 * a"])
        #expect(await mock.nextSentLine(timeout: .milliseconds(20)) == nil)
    }

    @Test func closeEndsStreamAndRejectsSends() async throws {
        let mock = MockTransport()
        let stream = try await mock.open()
        #expect(mock.isOpen)
        await mock.close()
        #expect(mock.isClosed)
        var iterator = stream.makeAsyncIterator()
        #expect(try await iterator.next() == nil)
        await #expect(throws: IRCTransportError.notConnected) { try await mock.send("x") }
        #expect(await mock.nextSentLine() == nil)
    }

    @Test func finishWithErrorPropagates() async throws {
        struct Boom: Error {}
        let mock = MockTransport()
        let stream = try await mock.open()
        mock.finish(throwing: Boom())
        await #expect(throws: Boom.self) {
            for try await _ in stream {}
        }
    }

    @Test func openErrorAndDoubleOpen() async throws {
        let failing = MockTransport(openError: IRCTransportError.connectionFailed("refused"))
        await #expect(throws: IRCTransportError.connectionFailed("refused")) { _ = try await failing.open() }
        let mock = MockTransport()
        _ = try await mock.open()
        await #expect(throws: IRCTransportError.alreadyOpened) { _ = try await mock.open() }
    }

    @Test func responderScriptsReplies() async throws {
        let mock = MockTransport { line in
            line.hasPrefix("PING ") ? ["PONG " + line.dropFirst(5)] : []
        }
        let stream = try await mock.open()
        try await mock.send("PING x")
        var iterator = stream.makeAsyncIterator()
        #expect(try await iterator.next() == "PONG x")
    }

    @Test func nextSentLineWherePredicate() async throws {
        let mock = MockTransport()
        _ = try await mock.open()
        for line in ["A", "B", "C"] { try await mock.send(line) }
        #expect(await mock.nextSentLine(where: { $0 == "C" }) == "C")
    }

    @Test func factoryCreatesFreshTransports() async throws {
        let factory = MockTransportFactory()
        let config = IRCClientConfig(host: "h", nick: "n")
        let first = factory.makeTransport(config)
        let second = factory.makeTransport(config)
        #expect(factory.transports.count == 2)
        #expect(first as? MockTransport !== second as? MockTransport)
        #expect(await factory.waitForTransport(count: 2) === second as? MockTransport)
    }

    @Test func clientIdentityEquality() {
        // Can't easily mint a SecIdentity in a unit test; just check the
        // error path of PKCS#12 import.
        #expect(throws: IRCTransportError.self) {
            _ = try ClientIdentity.importPKCS12(Data([0, 1, 2]), password: "x")
        }
    }
}
