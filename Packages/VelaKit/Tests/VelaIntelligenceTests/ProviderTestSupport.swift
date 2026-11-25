// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Synchronization
import VelaFoundation
import VelaStore
@testable import VelaIntelligence

/// A fake HTTP server for the provider tests: requests to its own host
/// (`stub-<uuid>.test`) are answered from a queue of replies (the last
/// one repeats) and recorded, body included. Nothing reaches the network,
/// and each server has its own host, so tests run side by side.
nonisolated final class StubServer: Sendable {
    /// One answer: a status, headers and the body in chunks (each delivered
    /// separately, like a stream), or a connection failure.
    struct Reply: Sendable {
        var status = 200
        var headers: [String: String] = [:]
        var chunks: [Data] = []
        var failure: URLError.Code?

        static func json(_ status: Int = 200, _ body: String, headers: [String: String] = [:]) -> Reply {
            Reply(status: status, headers: headers.merging(["Content-Type": "application/json"]) { $1 }, chunks: [Data(body.utf8)])
        }

        /// Server-sent events: each `data:` payload as its own chunk.
        static func events(_ payloads: [String], headers: [String: String] = [:]) -> Reply {
            Reply(
                status: 200,
                headers: headers.merging(["Content-Type": "text/event-stream"]) { $1 },
                chunks: payloads.map { Data("data: \($0)\n\n".utf8) }
            )
        }

        static func fail(_ code: URLError.Code) -> Reply {
            Reply(failure: code)
        }
    }

    /// A request as the server saw it.
    struct Request: Sendable {
        var url: URL
        var method: String
        var headers: [String: String]
        var body: Data

        var json: JSONValue? { try? JSONDecoder().decode(JSONValue.self, from: body) }
        var bodyText: String { String(decoding: body, as: UTF8.self) }

        func header(_ name: String) -> String? {
            headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
        }
    }

    let host = "stub-\(UUID().uuidString.lowercased()).test"
    private let state = Mutex<(replies: [Reply], requests: [Request])>(([], []))
    /// Answers each request from what it asks, instead of the queue.
    private let handler: (@Sendable (Request) -> Reply)?

    var baseURL: URL { URL(string: "https://\(host)/v1")! }

    init(_ replies: [Reply]) {
        handler = nil
        state.withLock { $0.replies = replies }
        StubURLProtocol.servers.withLock { $0[host] = self }
    }

    init(handler: @escaping @Sendable (Request) -> Reply) {
        self.handler = handler
        StubURLProtocol.servers.withLock { $0[host] = self }
    }

    deinit {
        StubURLProtocol.servers.withLock { $0[host] = nil }
    }

    var requests: [Request] { state.withLock { $0.requests } }

    func reply(to request: Request) -> Reply {
        let queued: Reply? = state.withLock { state in
            state.requests.append(request)
            guard handler == nil else { return nil }
            guard !state.replies.isEmpty else { return .json(500, "{}") }
            return state.replies.count > 1 ? state.replies.removeFirst() : state.replies[0]
        }
        return queued ?? handler!(request)
    }

    /// A session configuration whose requests go to the stub servers.
    static var configuration: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return configuration
    }
}

/// Answers requests to a ``StubServer``'s host.
nonisolated final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    static let servers = Mutex<[String: StubServer]>([:])

    override class func canInit(with request: URLRequest) -> Bool {
        guard let host = request.url?.host() else { return false }
        return servers.withLock { $0[host] != nil }
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let host = url.host(), let server = Self.servers.withLock({ $0[host] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        let captured = StubServer.Request(
            url: url,
            method: request.httpMethod ?? "GET",
            headers: request.allHTTPHeaderFields ?? [:],
            body: Self.body(of: request)
        )
        let reply = server.reply(to: captured)
        if let failure = reply.failure {
            client?.urlProtocol(self, didFailWithError: URLError(failure))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        for chunk in reply.chunks {
            client?.urlProtocol(self, didLoad: chunk)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// URL loading moves a request's body into a stream.
    private static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

/// Retries' waits, recorded instead of waited for.
nonisolated final class WaitRecorder: Sendable {
    private let waits = Mutex<[Duration]>([])
    var recorded: [Duration] { waits.withLock { $0 } }

    var sleep: @Sendable (Duration) async throws -> Void {
        { [self] duration in waits.withLock { $0.append(duration) } }
    }
}

/// Providers and APIs wired to stub servers.
nonisolated enum ProviderFixtures {
    static let identity = AIProviderIdentity(id: "test", name: "Test Provider")

    static func client(_ waits: WaitRecorder = WaitRecorder()) -> AIHTTPClient {
        var client = AIHTTPClient(session: AIHTTPClient.makeSession(requestTimeout: 10, resourceTimeout: 30, configuration: StubServer.configuration))
        client.sleep = waits.sleep
        return client
    }

    static func call(
        _ model: String,
        thinking: Bool? = true,
        instructions: String = "Summarize.",
        prompt: String = "[1] alice: hello",
        limit: Int = 500
    ) -> AIModelCall {
        AIModelCall(model: AIModelInfo(id: model, thinkingControl: thinking), instructions: instructions, prompt: prompt, maximumResponseTokens: limit)
    }

    /// Everything `api` streams for `call`, joined, or the error.
    static func collect(_ api: some AIProviderAPI, _ call: AIModelCall) async -> Result<String, Error> {
        do {
            var text = ""
            for try await piece in api.stream(call) { text += piece }
            return .success(text)
        } catch {
            return .failure(error)
        }
    }

    /// The failure reason in an error, if it's a provider failure.
    static func reason(_ error: Error?) -> AIProviderFailure.Reason? {
        switch error {
        case let CatchUpModelError.provider(failure)?: failure.reason
        case let CatchUpError.provider(failure)?: failure.reason
        default: nil
        }
    }

    // MARK: Canned answers

    /// An Anthropic stream writing `pieces`, with a thinking block first,
    /// stopping for `stopReason`.
    static func anthropicEvents(_ pieces: [String], stopReason: String = "end_turn") -> StubServer.Reply {
        var events = [
            #"{"type":"message_start","message":{"id":"msg_1","type":"message","role":"assistant","content":[]}}"#,
            #"{"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"secret reasoning"}}"#,
            #"{"type":"content_block_stop","index":0}"#,
            #"{"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}"#,
        ]
        for piece in pieces {
            events.append(#"{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":\#(quoted(piece))}}"#)
        }
        events.append(#"{"type":"content_block_stop","index":1}"#)
        events.append(#"{"type":"message_delta","delta":{"stop_reason":"\#(stopReason)"},"usage":{"output_tokens":12}}"#)
        events.append(#"{"type":"message_stop"}"#)
        return .events(events)
    }

    static func openAIEvents(_ pieces: [String]) -> StubServer.Reply {
        var events = [#"{"type":"response.created","response":{"id":"resp_1","status":"in_progress"}}"#]
        for piece in pieces {
            events.append(#"{"type":"response.output_text.delta","item_id":"msg_1","output_index":0,"content_index":0,"delta":\#(quoted(piece))}"#)
        }
        events.append(#"{"type":"response.completed","response":{"id":"resp_1","status":"completed"}}"#)
        return .events(events)
    }

    static func geminiEvents(_ pieces: [String], finishReason: String = "STOP") -> StubServer.Reply {
        var events = [#"{"candidates":[{"content":{"parts":[{"text":"thinking hard","thought":true}],"role":"model"}}]}"#]
        for (index, piece) in pieces.enumerated() {
            let finish = index == pieces.count - 1 ? #","finishReason":"\#(finishReason)""# : ""
            events.append(#"{"candidates":[{"content":{"parts":[{"text":\#(quoted(piece))}],"role":"model"}\#(finish)}]}"#)
        }
        return .events(events)
    }

    static func chatEvents(_ pieces: [String], finishReason: String = "stop") -> StubServer.Reply {
        var events: [String] = []
        for piece in pieces {
            events.append(#"{"id":"c1","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"content":\#(quoted(piece))},"finish_reason":null}]}"#)
        }
        events.append(#"{"id":"c1","object":"chat.completion.chunk","choices":[{"index":0,"delta":{},"finish_reason":"\#(finishReason)"}]}"#)
        events.append("[DONE]")
        return .events(events)
    }

    static func quoted(_ text: String) -> String {
        String(decoding: try! JSONEncoder().encode(text), as: UTF8.self)
    }
}
