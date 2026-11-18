// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// The outcome of a capped HTTP fetch.
struct HTTPFetchResult: Sendable {
    /// The final response (after redirects).
    var response: HTTPURLResponse
    var body: Data
    /// False when the body was truncated, the transfer was stopped early,
    /// or the body was deliberately skipped.
    var isComplete: Bool

    /// MIME type without parameters, lowercased (`text/html`).
    var mimeType: String? { response.normalizedMIMEType }
    var finalURL: URL? { response.url }
}

extension HTTPURLResponse {
    var normalizedMIMEType: String? {
        guard let header = value(forHTTPHeaderField: "Content-Type") ?? mimeType else { return nil }
        let type = header.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        return type.isEmpty ? nil : type
    }
}

/// Streams an HTTP response body with a byte cap, an optional early stop,
/// and a policy check on every redirect. Built on a per-task delegate so the
/// body arrives in chunks rather than byte by byte.
enum HTTPFetcher {
    enum Overflow: Sendable {
        /// Keep the first `maxBytes` and stop.
        case truncate
        /// Fail with `MediaError.tooLarge`.
        case fail
    }

    enum BodyDisposition: Sendable {
        case read
        /// Finish with the response alone (e.g. it turned out to be an image
        /// when we were looking for HTML).
        case skip
    }

    struct Options: Sendable {
        var maxBytes: Int
        var overflow: Overflow = .fail
        /// Which statuses count as an answer; any other fails the fetch with
        /// `MediaError.http`. A bot check's page arrives with 403 or 503, and
        /// is only told from an error page by reading it.
        var acceptsStatus: @Sendable (Int) -> Bool = { (200..<300).contains($0) }
        /// Called for each redirect target; returning an error fails the
        /// fetch with it (e.g. `MediaError.siteBlocked` naming the reason).
        var checkRedirect: @Sendable (URL) -> MediaError? = { _ in nil }
        /// Decide what to do once headers arrive; throwing fails the fetch.
        var inspectResponse: @Sendable (HTTPURLResponse) throws -> BodyDisposition = { _ in .read }
        /// Called after each chunk with the body so far and where the new
        /// chunk starts; returning true stops the transfer early.
        var shouldStop: (@Sendable (Data, Int) -> Bool)?
    }

    static func fetch(_ request: URLRequest, session: URLSession, options: Options) async throws -> HTTPFetchResult {
        try Task.checkCancellation()
        let delegate = StreamingDelegate(options: options)
        let task = session.dataTask(with: request)
        task.delegate = delegate

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                delegate.begin(continuation, task: task)
            }
        } onCancel: {
            task.cancel()
        }
    }
}

private final class StreamingDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let options: HTTPFetcher.Options
    // All mutable state below is guarded by `lock`.
    private let lock = NSLock()
    private var continuation: CheckedContinuation<HTTPFetchResult, any Error>?
    private var response: HTTPURLResponse?
    private var body = Data()
    private var finished = false
    /// Set when we cancel the task ourselves after resuming the continuation.
    private var pendingResult: Result<HTTPFetchResult, any Error>?

    init(options: HTTPFetcher.Options) {
        self.options = options
    }

    func begin(_ continuation: CheckedContinuation<HTTPFetchResult, any Error>, task: URLSessionDataTask) {
        lock.lock()
        if let pendingResult {
            lock.unlock()
            continuation.resume(with: pendingResult)
            return
        }
        self.continuation = continuation
        lock.unlock()
        task.resume()
    }

    /// Resolves the fetch exactly once.
    private func finish(_ result: Result<HTTPFetchResult, any Error>) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        let continuation = self.continuation
        self.continuation = nil
        if continuation == nil { pendingResult = result }
        lock.unlock()
        continuation?.resume(with: result)
    }

    // MARK: URLSessionTaskDelegate

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        let refusal: MediaError?
        if let url = request.url {
            refusal = options.checkRedirect(url)
        } else {
            refusal = .blockedByPolicy
        }
        if let refusal {
            finish(.failure(refusal))
            completionHandler(nil)
            task.cancel()
        } else {
            completionHandler(request)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        if let error {
            let mapped: any Error = (error as? URLError)?.code == .cancelled ? CancellationError() : error
            finish(.failure(mapped))
            return
        }
        lock.lock()
        let response = self.response
        let body = self.body
        lock.unlock()
        if let response {
            finish(.success(HTTPFetchResult(response: response, body: body, isComplete: true)))
        } else {
            finish(.failure(MediaError.invalidResponse))
        }
    }

    // MARK: URLSessionDataDelegate

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        guard let http = response as? HTTPURLResponse else {
            finish(.failure(MediaError.invalidResponse))
            completionHandler(.cancel)
            return
        }
        guard options.acceptsStatus(http.statusCode) else {
            finish(.failure(MediaError.http(http.statusCode)))
            completionHandler(.cancel)
            return
        }
        if options.overflow == .fail, http.expectedContentLength > Int64(options.maxBytes) {
            finish(.failure(MediaError.tooLarge))
            completionHandler(.cancel)
            return
        }
        let disposition: HTTPFetcher.BodyDisposition
        do {
            disposition = try options.inspectResponse(http)
        } catch {
            finish(.failure(error))
            completionHandler(.cancel)
            return
        }
        if disposition == .skip {
            finish(.success(HTTPFetchResult(response: http, body: Data(), isComplete: false)))
            completionHandler(.cancel)
            return
        }
        lock.lock()
        self.response = http
        if http.expectedContentLength > 0 {
            body.reserveCapacity(Int(min(http.expectedContentLength, Int64(options.maxBytes))))
        }
        lock.unlock()
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        guard !finished, let response else {
            lock.unlock()
            return
        }
        let chunkStart = body.count
        body.append(data)
        var outcome: Result<HTTPFetchResult, any Error>?
        if body.count > options.maxBytes {
            switch options.overflow {
            case .fail:
                outcome = .failure(MediaError.tooLarge)
            case .truncate:
                body.removeSubrange(options.maxBytes...)
                outcome = .success(HTTPFetchResult(response: response, body: body, isComplete: false))
            }
        } else if let shouldStop = options.shouldStop, shouldStop(body, chunkStart) {
            outcome = .success(HTTPFetchResult(response: response, body: body, isComplete: false))
        }
        lock.unlock()

        if let outcome {
            finish(outcome)
            dataTask.cancel()
        }
    }
}
