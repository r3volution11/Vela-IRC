// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Network
import Security
import Synchronization

/// A line-oriented connection to an IRC server.
public protocol IRCTransport: Sendable {
    /// Connects and returns the stream of received lines (no CRLF). Throws if
    /// the connection can't be established. The stream finishes when the
    /// server closes the connection and throws on network errors.
    func open() async throws -> AsyncThrowingStream<String, Error>
    /// Writes `line` followed by CRLF.
    func send(_ line: String) async throws
    /// Closes the connection and finishes the receive stream. Idempotent.
    func close() async
}

/// Errors surfaced by transports.
public enum IRCTransportError: Error, LocalizedError, Sendable, Equatable {
    case alreadyOpened
    case notConnected
    case connectionFailed(String)
    case certificateRejected(String)
    case lineTooLong
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .alreadyOpened: "The connection was already opened."
        case .notConnected: "Not connected."
        case .connectionFailed(let reason): reason
        case .certificateRejected(let reason): "The server's TLS certificate was rejected: \(reason)"
        case .lineTooLong: "The server sent a line that is too long."
        case .cancelled: "The connection was cancelled."
        }
    }
}

/// A TLS client certificate identity (for SASL EXTERNAL / CertFP).
public struct ClientIdentity: @unchecked Sendable, Hashable {
    // SecIdentity is an immutable CF object; sharing it across threads is safe.
    public let identity: SecIdentity

    public init(_ identity: SecIdentity) {
        self.identity = identity
    }

    public init(identity: SecIdentity) {
        self.identity = identity
    }

    public static func == (lhs: ClientIdentity, rhs: ClientIdentity) -> Bool {
        CFEqual(lhs.identity, rhs.identity)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(CFHash(identity))
    }

    /// Imports the first identity from PKCS#12 data (a `.p12` file).
    public static func importPKCS12(_ data: Data, password: String) throws -> ClientIdentity {
        let options = [kSecImportExportPassphrase as String: password] as CFDictionary
        var items: CFArray?
        let status = SecPKCS12Import(data as CFData, options, &items)
        guard status == errSecSuccess,
              let array = items as? [[String: Any]],
              let first = array.first,
              let value = first[kSecImportItemIdentity as String]
        else {
            let message = (SecCopyErrorMessageString(status, nil) as String?) ?? "OSStatus \(status)"
            throw IRCTransportError.connectionFailed("Could not import client certificate: \(message)")
        }
        // swiftlint:disable:next force_cast
        return ClientIdentity(value as! SecIdentity)
    }
}

// MARK: - Line framing

/// Splits a byte stream into IRC lines on `\n`, dropping a trailing `\r`.
/// Each line is decoded as UTF-8, falling back to ISO-8859-1 when invalid.
/// Empty lines are skipped.
struct LineFramer: Sendable {
    /// Lines longer than this without a newline are an error. IRCv3 allows
    /// 8191 bytes of tags plus a 512-byte message; leave generous headroom.
    static let maximumLineLength = 64 * 1024

    private var buffer: [UInt8] = []

    /// Appends received bytes and returns any complete lines. Throws
    /// `IRCTransportError.lineTooLong` when the buffer overflows.
    mutating func append(_ bytes: some Sequence<UInt8>) throws -> [String] {
        buffer.append(contentsOf: bytes)
        var lines: [String] = []
        var start = 0
        while let newline = buffer[start...].firstIndex(of: 0x0A) {
            var end = newline
            if end > start && buffer[end - 1] == 0x0D { end -= 1 }
            if end > start { lines.append(Self.decode(buffer[start..<end])) }
            start = newline + 1
        }
        if start > 0 { buffer.removeFirst(start) }
        if buffer.count > Self.maximumLineLength {
            buffer.removeAll()
            throw IRCTransportError.lineTooLong
        }
        return lines
    }

    /// Returns a final unterminated line, if any, and clears the buffer.
    mutating func flush() -> String? {
        defer { buffer.removeAll() }
        var bytes = buffer[...]
        while let last = bytes.last, last == 0x0D { bytes = bytes.dropLast() }
        return bytes.isEmpty ? nil : Self.decode(bytes)
    }

    static func decode(_ bytes: ArraySlice<UInt8>) -> String {
        if let string = String(validating: bytes, as: UTF8.self) { return string }
        // ISO-8859-1 maps every byte to the scalar of the same value.
        var scalars = String.UnicodeScalarView()
        for byte in bytes { scalars.append(Unicode.Scalar(byte)) }
        return String(scalars)
    }
}

// MARK: - Network.framework transport

/// A TCP/TLS transport built on `NWConnection`.
public final class NetworkTransport: IRCTransport {
    public let host: String
    public let port: UInt16
    public let useTLS: Bool
    public let allowInvalidCertificates: Bool
    public let clientIdentity: ClientIdentity?

    private let queue = DispatchQueue(label: "app.vela.irc.transport")
    private let state = Mutex(State())

    private struct State {
        var connection: NWConnection?
        var continuation: AsyncThrowingStream<String, Error>.Continuation?
        var openContinuation: CheckedContinuation<Void, Error>?
        var framer = LineFramer()
        var trustFailure: String?
        var opened = false
        var closed = false
    }

    public init(
        host: String,
        port: UInt16,
        useTLS: Bool,
        allowInvalidCertificates: Bool = false,
        clientIdentity: ClientIdentity? = nil
    ) {
        self.host = host
        self.port = port
        self.useTLS = useTLS
        self.allowInvalidCertificates = allowInvalidCertificates
        self.clientIdentity = clientIdentity
    }

    public convenience init(config: IRCClientConfig) {
        self.init(
            host: config.host,
            port: config.port,
            useTLS: config.useTLS,
            allowInvalidCertificates: config.allowInvalidCertificates,
            clientIdentity: config.clientIdentity
        )
    }

    deinit {
        state.withLock { $0.connection }?.cancel()
    }

    public func open() async throws -> AsyncThrowingStream<String, Error> {
        let (stream, continuation) = AsyncThrowingStream<String, Error>.makeStream()
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port) ?? .any,
            using: makeParameters()
        )
        try state.withLock { state in
            guard !state.opened else { throw IRCTransportError.alreadyOpened }
            state.opened = true
            state.connection = connection
            state.continuation = continuation
        }
        continuation.onTermination = { [weak self] _ in
            self?.cancelConnection()
        }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (open: CheckedContinuation<Void, Error>) in
                let alreadyClosed = state.withLock { state in
                    if state.closed { return true }
                    state.openContinuation = open
                    return false
                }
                if alreadyClosed {
                    open.resume(throwing: IRCTransportError.cancelled)
                    return
                }
                connection.stateUpdateHandler = { [weak self] newState in
                    self?.handleState(newState)
                }
                connection.start(queue: queue)
            }
        } onCancel: { [weak self] in
            self?.cancelConnection()
        }
        return stream
    }

    public func send(_ line: String) async throws {
        guard let connection = state.withLock({ $0.closed ? nil : $0.connection }) else {
            throw IRCTransportError.notConnected
        }
        let data = Data((line + "\r\n").utf8)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: Self.describe(error, trustFailure: nil))
                } else {
                    continuation.resume()
                }
            })
        }
    }

    public func close() async {
        cancelConnection()
    }

    // MARK: Internals

    private func cancelConnection() {
        let (connection, continuation, open) = state.withLock { state in
            state.closed = true
            let result = (state.connection, state.continuation, state.openContinuation)
            state.continuation = nil
            state.openContinuation = nil
            return result
        }
        connection?.cancel()
        open?.resume(throwing: IRCTransportError.cancelled)
        continuation?.finish()
    }

    private func handleState(_ newState: NWConnection.State) {
        switch newState {
        case .ready:
            let (open, connection) = state.withLock { state in
                let open = state.openContinuation
                state.openContinuation = nil
                return (open, state.connection)
            }
            open?.resume()
            if let connection { receiveNext(on: connection) }

        case .waiting(let error), .failed(let error):
            // `.waiting` means the connection can't currently be established
            // (refused, unreachable, DNS failure). An IRC client wants to
            // surface that and let its own reconnect policy decide.
            let (open, continuation, connection, trustFailure) = state.withLock { state in
                let result = (state.openContinuation, state.continuation, state.connection, state.trustFailure)
                state.openContinuation = nil
                state.continuation = nil
                state.closed = true
                return result
            }
            let failure = Self.describe(error, trustFailure: trustFailure)
            connection?.cancel()
            if let open {
                open.resume(throwing: failure)
                continuation?.finish()
            } else {
                continuation?.finish(throwing: failure)
            }

        case .cancelled:
            let (open, continuation) = state.withLock { state in
                let result = (state.openContinuation, state.continuation)
                state.openContinuation = nil
                state.continuation = nil
                state.closed = true
                return result
            }
            open?.resume(throwing: IRCTransportError.cancelled)
            continuation?.finish()

        case .setup, .preparing:
            break

        @unknown default:
            break
        }
    }

    private func receiveNext(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var lines: [String] = []
            var failure: Error?
            var finalLine: String?
            let continuation = state.withLock { state -> AsyncThrowingStream<String, Error>.Continuation? in
                if let data, !data.isEmpty {
                    do {
                        lines = try state.framer.append(data)
                    } catch {
                        failure = error
                    }
                }
                if isComplete || error != nil || failure != nil {
                    finalLine = isComplete ? state.framer.flush() : nil
                    let continuation = state.continuation
                    state.continuation = nil
                    return continuation
                }
                return state.continuation
            }
            guard let continuation else { return }
            for line in lines { continuation.yield(line) }
            if let error {
                continuation.finish(throwing: Self.describe(error, trustFailure: nil))
            } else if let failure {
                continuation.finish(throwing: failure)
                connection.cancel()
            } else if isComplete {
                if let finalLine { continuation.yield(finalLine) }
                continuation.finish()
            } else {
                receiveNext(on: connection)
            }
        }
    }

    private func recordTrustFailure(_ message: String) {
        state.withLock { $0.trustFailure = message }
    }

    private func makeParameters() -> NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 60
        tcp.keepaliveInterval = 20
        tcp.keepaliveCount = 3
        tcp.noDelay = true

        guard useTLS else { return NWParameters(tls: nil, tcp: tcp) }

        let tls = NWProtocolTLS.Options()
        let options = tls.securityProtocolOptions
        sec_protocol_options_set_min_tls_protocol_version(options, .TLSv12)
        if let clientIdentity, let identity = sec_identity_create(clientIdentity.identity) {
            sec_protocol_options_set_local_identity(options, identity)
        }
        let allowInvalid = allowInvalidCertificates
        let host = host
        sec_protocol_options_set_verify_block(options, { [weak self] _, trustRef, complete in
            if allowInvalid {
                complete(true)
                return
            }
            let trust = sec_trust_copy_ref(trustRef).takeRetainedValue()
            SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, host as CFString))
            var error: CFError?
            let trusted = SecTrustEvaluateWithError(trust, &error)
            if !trusted {
                let reason = error.map { CFErrorCopyDescription($0) as String } ?? "certificate is not trusted"
                self?.recordTrustFailure(reason)
            }
            complete(trusted)
        }, queue)

        return NWParameters(tls: tls, tcp: tcp)
    }

    private static func describe(_ error: NWError, trustFailure: String?) -> IRCTransportError {
        if let trustFailure { return .certificateRejected(trustFailure) }
        switch error {
        case .posix(let code):
            return .connectionFailed(String(cString: strerror(code.rawValue)))
        case .dns(let code):
            if code == kDNSServiceErr_NoSuchRecord || code == kDNSServiceErr_NoSuchName {
                return .connectionFailed("Host not found")
            }
            return .connectionFailed("DNS error \(code)")
        case .tls(let status):
            let message = (SecCopyErrorMessageString(status, nil) as String?) ?? "OSStatus \(status)"
            return .connectionFailed("TLS error: \(message)")
        default:
            return .connectionFailed(error.debugDescription)
        }
    }
}

// MARK: - Test double

/// An in-memory transport for tests. Inject server lines with `receive(_:)`,
/// end the connection with `finish(throwing:)`, and observe what the client
/// wrote via `sentLines` / `nextSentLine(timeout:)`.
///
/// Lines injected before `open()` are buffered and delivered in order.
public final class MockTransport: IRCTransport {
    private struct Waiter {
        var id: UInt64
        var continuation: CheckedContinuation<String?, Never>
        var timer: Task<Void, Never>?
    }

    private struct State {
        var sent: [String] = []
        var cursor = 0
        var waiters: [Waiter] = []
        var nextWaiterID: UInt64 = 0
        var opened = false
        var closed = false
        var openError: (any Error)?
        var responder: (@Sendable (String) -> [String])?
        var continuation: AsyncThrowingStream<String, Error>.Continuation
    }

    private let state: Mutex<State>
    private let stream: AsyncThrowingStream<String, Error>

    /// - Parameters:
    ///   - openError: when set, `open()` throws it.
    ///   - responder: called for every sent line; returned lines are injected
    ///     as if the server had sent them (a scripted server).
    public init(openError: (any Error)? = nil, responder: (@Sendable (String) -> [String])? = nil) {
        let (stream, continuation) = AsyncThrowingStream<String, Error>.makeStream()
        self.stream = stream
        state = Mutex(State(openError: openError, responder: responder, continuation: continuation))
    }

    public func open() async throws -> AsyncThrowingStream<String, Error> {
        try state.withLock { state in
            if let error = state.openError { throw error }
            guard !state.opened else { throw IRCTransportError.alreadyOpened }
            state.opened = true
        }
        return stream
    }

    public func send(_ line: String) async throws {
        let (waiter, responder) = try state.withLock { state -> (Waiter?, (@Sendable (String) -> [String])?) in
            guard state.opened, !state.closed else { throw IRCTransportError.notConnected }
            state.sent.append(line)
            var waiter: Waiter?
            if !state.waiters.isEmpty {
                waiter = state.waiters.removeFirst()
                state.cursor += 1
            }
            return (waiter, state.responder)
        }
        waiter?.timer?.cancel()
        waiter?.continuation.resume(returning: line)
        if let responder {
            for reply in responder(line) { receive(reply) }
        }
    }

    public func close() async {
        finish(throwing: nil)
    }

    // MARK: Server side

    /// Delivers a line to the client as if the server had sent it.
    public func receive(_ line: String) {
        let continuation = state.withLock { $0.closed ? nil : $0.continuation }
        continuation?.yield(line)
    }

    /// Delivers several lines in order.
    public func receive(lines: [String]) {
        for line in lines { receive(line) }
    }

    /// Ends the connection from the server side: the receive stream finishes
    /// (throwing `error` when given) and further sends fail.
    public func finish(throwing error: (any Error)? = nil) {
        let (continuation, waiters) = state.withLock { state -> (AsyncThrowingStream<String, Error>.Continuation?, [Waiter]) in
            guard !state.closed else { return (nil, []) }
            state.closed = true
            let waiters = state.waiters
            state.waiters = []
            return (state.continuation, waiters)
        }
        if let error {
            continuation?.finish(throwing: error)
        } else {
            continuation?.finish()
        }
        for waiter in waiters {
            waiter.timer?.cancel()
            waiter.continuation.resume(returning: nil)
        }
    }

    /// Replaces the scripted responder.
    public func setResponder(_ responder: (@Sendable (String) -> [String])?) {
        state.withLock { $0.responder = responder }
    }

    // MARK: Observation

    /// Every line written so far, in order.
    public var sentLines: [String] { state.withLock { $0.sent } }

    public var isOpen: Bool { state.withLock { $0.opened && !$0.closed } }
    public var isClosed: Bool { state.withLock { $0.closed } }

    /// Returns the next sent line not yet returned by this method, waiting
    /// for it if necessary. Returns nil if the transport closes or `timeout`
    /// elapses first.
    public func nextSentLine(timeout: Duration = .seconds(5)) async -> String? {
        await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            let immediate: String?? = state.withLock { state in
                if state.cursor < state.sent.count {
                    defer { state.cursor += 1 }
                    return .some(state.sent[state.cursor])
                }
                if state.closed { return .some(nil) }
                let id = state.nextWaiterID
                state.nextWaiterID += 1
                let timer = Task { [weak self] in
                    do { try await Task.sleep(for: timeout) } catch { return }
                    self?.expireWaiter(id)
                }
                state.waiters.append(Waiter(id: id, continuation: continuation, timer: timer))
                return nil
            }
            if let immediate { continuation.resume(returning: immediate) }
        }
    }

    /// Like `nextSentLine`, parsed.
    public func nextSentMessage(timeout: Duration = .seconds(5)) async -> IRCMessage? {
        guard let line = await nextSentLine(timeout: timeout) else { return nil }
        return IRCMessage(line: line)
    }

    /// Skips sent lines until one satisfies `predicate`; nil on close/timeout.
    public func nextSentLine(
        timeout: Duration = .seconds(5),
        where predicate: @Sendable (String) -> Bool
    ) async -> String? {
        let deadline = ContinuousClock.now + timeout
        while true {
            let remaining = deadline - ContinuousClock.now
            guard remaining > .zero, let line = await nextSentLine(timeout: remaining) else { return nil }
            if predicate(line) { return line }
        }
    }

    private func expireWaiter(_ id: UInt64) {
        let waiter = state.withLock { state -> Waiter? in
            guard let index = state.waiters.firstIndex(where: { $0.id == id }) else { return nil }
            return state.waiters.remove(at: index)
        }
        waiter?.continuation.resume(returning: nil)
    }
}

/// Hands out a fresh `MockTransport` per connection attempt, so tests can
/// drive reconnects. Use `makeTransport` as an `IRCClient` transport factory.
public final class MockTransportFactory: Sendable {
    private let state = Mutex<[MockTransport]>([])
    private let configure: @Sendable (MockTransport, Int) -> Void

    /// - Parameter configure: called with each new transport and its index
    ///   (0 for the first connection) before it is handed to the client.
    public init(configure: @escaping @Sendable (MockTransport, Int) -> Void = { _, _ in }) {
        self.configure = configure
    }

    /// Every transport created so far.
    public var transports: [MockTransport] { state.withLock { $0 } }

    /// The most recently created transport.
    public var latest: MockTransport? { state.withLock { $0.last } }

    public var makeTransport: @Sendable (IRCClientConfig) -> any IRCTransport {
        { [self] _ in
            let transport = MockTransport()
            let index = state.withLock { transports in
                transports.append(transport)
                return transports.count - 1
            }
            configure(transport, index)
            return transport
        }
    }

    /// Waits until at least `count` transports have been created.
    public func waitForTransport(count: Int, timeout: Duration = .seconds(5)) async -> MockTransport? {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            let transports = self.transports
            if transports.count >= count { return transports[count - 1] }
            try? await Task.sleep(for: .milliseconds(2))
        }
        return nil
    }
}
