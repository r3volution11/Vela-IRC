// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Network
import Synchronization
import Testing
@testable import VelaIRC

/// A one-connection plaintext TCP server on 127.0.0.1 for exercising
/// `NetworkTransport` end to end.
private final class LoopbackServer: Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "test.loopback")
    private let state = Mutex<(connection: NWConnection?, received: Data)>((nil, Data()))

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
    }

    /// Starts listening and returns the bound port.
    func start() async throws -> UInt16 {
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            state.withLock { $0.connection = connection }
            connection.start(queue: queue)
            receive(on: connection)
        }
        return try await withCheckedThrowingContinuation { continuation in
            let resumed = Mutex(false)
            listener.stateUpdateHandler = { [listener] newState in
                switch newState {
                case .ready:
                    if !resumed.withLock({ let was = $0; $0 = true; return was }) {
                        continuation.resume(returning: listener.port?.rawValue ?? 0)
                    }
                case .failed(let error):
                    if !resumed.withLock({ let was = $0; $0 = true; return was }) {
                        continuation.resume(throwing: error)
                    }
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data { state.withLock { $0.received.append(data) } }
            if !isComplete && error == nil { receive(on: connection) }
        }
    }

    func waitForConnection(timeout: Duration = .seconds(5)) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if state.withLock({ $0.connection != nil }) { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return false
    }

    func write(_ text: String) async {
        guard let connection = state.withLock({ $0.connection }) else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            connection.send(content: Data(text.utf8), completion: .contentProcessed { _ in continuation.resume() })
        }
    }

    func write(bytes: [UInt8]) async {
        guard let connection = state.withLock({ $0.connection }) else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            connection.send(content: Data(bytes), completion: .contentProcessed { _ in continuation.resume() })
        }
    }

    /// Half-closes the server side (sends FIN).
    func finishWriting() async {
        guard let connection = state.withLock({ $0.connection }) else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            connection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
                continuation.resume()
            })
        }
    }

    func receivedText(waitingFor expected: String, timeout: Duration = .seconds(5)) async -> String {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            let text = String(decoding: state.withLock { $0.received }, as: UTF8.self)
            if text.contains(expected) { return text }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return String(decoding: state.withLock { $0.received }, as: UTF8.self)
    }

    func stop() {
        listener.cancel()
        state.withLock { $0.connection }?.cancel()
    }
}

@Suite(.timeLimit(.minutes(1))) struct NetworkTransportTests {
    @Test func roundTripsLinesOverLoopback() async throws {
        let server = try LoopbackServer()
        defer { server.stop() }
        let port = try await server.start()

        let transport = NetworkTransport(host: "127.0.0.1", port: port, useTLS: false)
        let stream = try await transport.open()
        #expect(await server.waitForConnection())

        try await transport.send("NICK vela")
        #expect(await server.receivedText(waitingFor: "NICK vela\r\n") == "NICK vela\r\n")

        // Lines split across writes, bare LF, Latin-1 fallback, final line
        // without a terminator before EOF.
        await server.write("PING :one\r\nPRIVMSG #c :sp")
        await server.write("lit\nNOTICE x :")
        await server.write(bytes: [0x63, 0x61, 0x66, 0xE9, 0x0D, 0x0A])
        await server.write("ERROR :bye")
        await server.finishWriting()

        var lines: [String] = []
        for try await line in stream { lines.append(line) }
        #expect(lines == ["PING :one", "PRIVMSG #c :split", "NOTICE x :café", "ERROR :bye"])
        await transport.close()
    }

    @Test func closeFinishesStreamAndRejectsSends() async throws {
        let server = try LoopbackServer()
        defer { server.stop() }
        let port = try await server.start()

        let transport = NetworkTransport(host: "127.0.0.1", port: port, useTLS: false)
        let stream = try await transport.open()
        await transport.close()
        var iterator = stream.makeAsyncIterator()
        #expect(try await iterator.next() == nil)
        await #expect(throws: IRCTransportError.notConnected) { try await transport.send("x") }
        await #expect(throws: IRCTransportError.alreadyOpened) { _ = try await transport.open() }
    }

    @Test func refusedConnectionThrows() async throws {
        // Bind and immediately release a port so nothing is listening on it.
        let server = try LoopbackServer()
        let port = try await server.start()
        server.stop()
        try await Task.sleep(for: .milliseconds(50))

        let transport = NetworkTransport(host: "127.0.0.1", port: port, useTLS: false)
        await #expect(throws: IRCTransportError.self) { _ = try await transport.open() }
    }

    @Test func clientRegistersOverRealTransport() async throws {
        let server = try LoopbackServer()
        defer { server.stop() }
        let port = try await server.start()

        let config = IRCClientConfig(host: "127.0.0.1", port: port, useTLS: false, nick: "vela", floodPolicy: .disabled)
        let client = IRCClient(config: config)
        let events = EventRecorder(client.events)
        await client.connect()
        #expect(await server.waitForConnection())
        #expect(await server.receivedText(waitingFor: "USER").contains("CAP LS 302\r\nNICK vela\r\nUSER vela 0 * vela\r\n"))
        await server.write(":loop CAP * LS :\r\n")
        #expect(await server.receivedText(waitingFor: "CAP END").hasSuffix("CAP END\r\n"))
        await server.write(":loop 001 vela :Welcome\r\nPING :loop\r\n")
        #expect(await events.next { if case .registered(let nick) = $0 { nick } else { nil } } == "vela")
        #expect(await server.receivedText(waitingFor: "PONG").hasSuffix("PONG loop\r\n"))
        await client.disconnect(reason: "bye")
        #expect(await server.receivedText(waitingFor: "QUIT").hasSuffix("QUIT bye\r\n"))
    }
}
