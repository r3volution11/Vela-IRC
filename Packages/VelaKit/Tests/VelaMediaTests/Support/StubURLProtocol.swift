// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// A canned HTTP response for `StubServer`.
struct StubResponse: Sendable {
    var status = 200
    var headers: [String: String] = [:]
    var body = Data()
    /// Location for 3xx responses.
    var redirectTo: URL?
    /// Delay before the response headers are sent.
    var delay: TimeInterval = 0
    /// Body is delivered in chunks of this size, with `chunkDelay` between them.
    var chunkSize = 16 * 1024
    var chunkDelay: TimeInterval = 0

    static func html(_ html: String, status: Int = 200, contentType: String = "text/html; charset=utf-8") -> StubResponse {
        StubResponse(status: status, headers: ["Content-Type": contentType], body: Data(html.utf8))
    }

    static func data(_ data: Data, contentType: String?, includeLength: Bool = true) -> StubResponse {
        var headers: [String: String] = [:]
        if let contentType { headers["Content-Type"] = contentType }
        if includeLength { headers["Content-Length"] = String(data.count) }
        return StubResponse(headers: headers, body: data)
    }

    static func json(_ object: [String: any Sendable]) -> StubResponse {
        let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
        return StubResponse(headers: ["Content-Type": "application/json"], body: data)
    }

    static func redirect(to url: String, status: Int = 302) -> StubResponse {
        StubResponse(status: status, headers: ["Location": url], redirectTo: URL(string: url))
    }

    static func status(_ status: Int) -> StubResponse {
        StubResponse(status: status, headers: ["Content-Type": "text/plain"], body: Data("error".utf8))
    }
}

/// A fake web server reachable only through the sessions it vends.
/// Each server has its own token, so tests running in parallel never see
/// each other's routes. Unrouted requests get a 404.
final class StubServer: @unchecked Sendable {
    static let tokenHeader = "X-Vela-Stub-Token"

    let token = UUID().uuidString
    private let lock = NSLock()
    private var routes: [String: StubResponse] = [:]
    private var methodRoutes: [String: StubResponse] = [:]
    private var recorded: [URLRequest] = []
    private var deliveredChunks: [String: Int] = [:]

    init() {
        StubURLProtocol.register(self)
    }

    deinit {
        StubURLProtocol.unregister(token)
    }

    func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        configuration.httpAdditionalHeaders = [Self.tokenHeader: token]
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }

    /// Routes `url` (exact absolute string) to `response`; `method` limits it to e.g. "HEAD".
    func route(_ url: String, method: String? = nil, _ response: StubResponse) {
        lock.lock()
        defer { lock.unlock() }
        if let method {
            methodRoutes[method + " " + url] = response
        } else {
            routes[url] = response
        }
    }

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func requests(to url: String, method: String? = nil) -> [URLRequest] {
        requests.filter { $0.url?.absoluteString == url && (method == nil || $0.httpMethod == method) }
    }

    func chunksDelivered(for url: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return deliveredChunks[url] ?? 0
    }

    fileprivate func respond(to request: URLRequest) -> StubResponse {
        lock.lock()
        defer { lock.unlock() }
        recorded.append(request)
        let url = request.url?.absoluteString ?? ""
        let method = request.httpMethod ?? "GET"
        return methodRoutes[method + " " + url] ?? routes[url] ?? .status(404)
    }

    fileprivate func noteChunkDelivered(for url: String) {
        lock.lock()
        defer { lock.unlock() }
        deliveredChunks[url, default: 0] += 1
    }
}

final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var servers: [String: WeakServer] = [:]

    private struct WeakServer {
        weak var server: StubServer?
    }

    static func register(_ server: StubServer) {
        lock.lock()
        defer { lock.unlock() }
        servers[server.token] = WeakServer(server: server)
    }

    static func unregister(_ token: String) {
        lock.lock()
        defer { lock.unlock() }
        servers[token] = nil
    }

    private static func server(for request: URLRequest) -> StubServer? {
        guard let token = request.value(forHTTPHeaderField: StubServer.tokenHeader) else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return servers[token]?.server
    }

    private let stateLock = NSLock()
    private var stopped = false

    private var isStopped: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return stopped
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let server = Self.server(for: request), let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let stub = server.respond(to: request)
        let request = self.request
        let queue = DispatchQueue.global(qos: .userInitiated)
        queue.asyncAfter(deadline: .now() + stub.delay) { [self] in
            guard !isStopped else { return }
            var headers = stub.headers
            if let redirect = stub.redirectTo {
                headers["Location"] = redirect.absoluteString
                let response = HTTPURLResponse(url: url, statusCode: stub.status, httpVersion: "HTTP/1.1", headerFields: headers)!
                var next = URLRequest(url: redirect)
                next.httpMethod = request.httpMethod
                for (name, value) in request.allHTTPHeaderFields ?? [:] { next.setValue(value, forHTTPHeaderField: name) }
                client?.urlProtocol(self, wasRedirectedTo: next, redirectResponse: response)
                client?.urlProtocolDidFinishLoading(self)
                return
            }
            let response = HTTPURLResponse(url: url, statusCode: stub.status, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if request.httpMethod == "HEAD" || stub.body.isEmpty {
                client?.urlProtocolDidFinishLoading(self)
                return
            }
            deliver(stub, from: 0, url: url.absoluteString, server: server, queue: queue)
        }
    }

    private func deliver(_ stub: StubResponse, from offset: Int, url: String, server: StubServer, queue: DispatchQueue) {
        guard !isStopped else { return }
        let end = min(offset + max(1, stub.chunkSize), stub.body.count)
        client?.urlProtocol(self, didLoad: stub.body.subdata(in: offset..<end))
        server.noteChunkDelivered(for: url)
        if end >= stub.body.count {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        if stub.chunkDelay > 0 {
            queue.asyncAfter(deadline: .now() + stub.chunkDelay) { [self] in
                deliver(stub, from: end, url: url, server: server, queue: queue)
            }
        } else {
            deliver(stub, from: end, url: url, server: server, queue: queue)
        }
    }

    override func stopLoading() {
        stateLock.lock()
        stopped = true
        stateLock.unlock()
    }
}
