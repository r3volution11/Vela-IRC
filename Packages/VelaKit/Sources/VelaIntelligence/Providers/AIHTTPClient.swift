// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaFoundation

/// Who a request is for, as failures name it.
nonisolated struct AIProviderIdentity: Sendable, Hashable {
    var id: String
    var name: String
    /// A custom server: an address that doesn't answer is a server that
    /// isn't running, not the Mac being offline.
    var isCustomServer = false

    func failure(_ reason: AIProviderFailure.Reason, model: String? = nil) -> CatchUpModelError {
        .provider(AIProviderFailure(providerID: id, providerName: name, reason: reason, modelID: model))
    }
}

/// A non-2xx answer, as a provider's error handling sees it.
nonisolated struct AIHTTPError: Sendable {
    var status: Int
    /// The body, parsed, when it's JSON.
    var body: JSONValue?
    /// The body as text (the first 64 KB).
    var text: String
    /// How long the provider asked to wait (`retry-after`, `retry-after-ms`).
    var retryAfter: Duration?

    /// `error.message`, the common shape (Anthropic, OpenAI, Gemini,
    /// Ollama), or a top-level `message`, or an `error` that's a string.
    var message: String? {
        if let error = body?["error"] {
            if let text = error.stringValue { return text }
            if let text = error["message"]?.stringValue { return text }
        }
        return body?["message"]?.stringValue
    }

    /// `error.type` (Anthropic, OpenAI) or `error.status` (Gemini).
    var type: String? {
        body?["error"]?["type"]?.stringValue ?? body?["error"]?["status"]?.stringValue
    }

    /// `error.code` when it's a string (OpenAI's `insufficient_quota`).
    var code: String? {
        body?["error"]?["code"]?.stringValue
    }

    /// Every reason in Gemini's `error.details` (`API_KEY_INVALID`).
    var detailReasons: [String] {
        body?["error"]?["details"]?.arrayValue?.compactMap { $0["reason"]?.stringValue } ?? []
    }

    /// The provider's message, made fit to show (or the status).
    var displayMessage: String {
        AIProviderFailure.trimmed(message ?? "HTTP \(status)")
    }

    /// Mentions a context window that's too small for the request: each
    /// provider words it its own way.
    var saysContextExceeded: Bool {
        if code == "context_length_exceeded" { return true }
        let lower = (message ?? text).lowercased()
        return lower.contains("prompt is too long")
            || lower.contains("context length")
            || lower.contains("context window")
            || lower.contains("maximum context")
            || lower.contains("too many tokens")
            || (lower.contains("exceeds") && lower.contains("token"))
            || lower.contains("context the overflows")
    }

    /// Parses `retry-after-ms` or `retry-after` (seconds, or an HTTP date).
    static func retryAfter(_ response: HTTPURLResponse, now: Date = Date()) -> Duration? {
        if let value = response.value(forHTTPHeaderField: "retry-after-ms"), let ms = Double(value.trimmingCharacters(in: .whitespaces)), ms >= 0 {
            return .milliseconds(Int(ms.rounded(.up)))
        }
        guard let value = response.value(forHTTPHeaderField: "retry-after")?.trimmingCharacters(in: .whitespaces) else { return nil }
        if let seconds = Double(value), seconds >= 0 { return .milliseconds(Int((seconds * 1000).rounded(.up))) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let date = formatter.date(from: value) else { return nil }
        return .milliseconds(max(0, Int((date.timeIntervalSince(now) * 1000).rounded(.up))))
    }
}

/// How one provider's API reports trouble: which answers are worth
/// retrying, and what each failure means.
nonisolated protocol AIErrorClassifying: Sendable {
    var identity: AIProviderIdentity { get }
    /// Worth asking again after a wait: by default 429s and 5xx, except
    /// what ``failure(for:model:)`` says is a quota.
    func isRetryable(_ error: AIHTTPError) -> Bool
    /// The engine's error for an answer: `.contextExceeded`, `.declined`
    /// or `.provider(…)`.
    func failure(for error: AIHTTPError, model: String?) -> CatchUpModelError
}

nonisolated extension AIErrorClassifying {
    func isRetryable(_ error: AIHTTPError) -> Bool {
        guard error.status == 429 || error.status >= 500 else { return false }
        if case .provider(let failure) = failure(for: error, model: nil), failure.reason == .quota { return false }
        return true
    }

    /// What most providers mean by each status; providers refine it.
    func standardFailure(for error: AIHTTPError, model: String?) -> CatchUpModelError {
        if error.saysContextExceeded, error.status == 400 || error.status == 413 || error.status == 422 {
            return .contextExceeded
        }
        switch error.status {
        case 401: return identity.failure(.badKey)
        case 402: return identity.failure(.quota)
        case 403: return identity.failure(.other(error.displayMessage))
        case 404: return identity.failure(.modelNotFound, model: model)
        case 429: return identity.failure(.rateLimited)
        case 500...: return identity.failure(.overloaded)
        default: return identity.failure(.other(error.displayMessage))
        }
    }
}

/// Sends providers' requests. An ephemeral session (no cache, no cookies,
/// nothing on disk), with timeouts: the time between bytes and the time
/// for the whole answer. 429s and 5xx are retried up to ``maxRetries``
/// times, waiting as long as the provider asks (`retry-after`) when that's
/// at most ``maxRetryDelay``, before any of the answer has arrived; once
/// text is streaming, a failure ends it. Nothing here logs a request, an
/// answer or a key.
nonisolated struct AIHTTPClient: Sendable {
    let session: URLSession
    var maxRetries = 2
    var maxRetryDelay: Duration = .seconds(20)
    /// Waits between attempts (tests record the waits instead).
    var sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }

    /// The most of an error's body that's read.
    static let errorBodyLimit = 64 * 1024

    /// An ephemeral session for one kind of provider. `configuration` is
    /// for tests (a stub `URLProtocol`); its storage is cleared regardless.
    static func makeSession(
        requestTimeout: TimeInterval,
        resourceTimeout: TimeInterval = 600,
        configuration: URLSessionConfiguration = .ephemeral
    ) -> URLSession {
        let configuration = configuration
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = resourceTimeout
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }

    // MARK: Requests

    /// A JSON request: method, headers, and the body encoded.
    static func request(_ url: URL, method: String = "GET", headers: [String: String] = [:], body: JSONValue? = nil) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        if let body {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.withoutEscapingSlashes]
            request.httpBody = try? encoder.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    /// The body of a 2xx answer, parsed.
    func json(_ request: URLRequest, api: some AIErrorClassifying) async throws -> JSONValue {
        let bytes = try await open(request, api: api, model: nil)
        var data = Data()
        do {
            for try await byte in bytes { data.append(byte) }
        } catch {
            throw transportFailure(error, identity: api.identity)
        }
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            throw api.identity.failure(.other("The answer wasn't JSON."))
        }
        return value
    }

    /// A streamed answer's events: each `data:` line of the server-sent
    /// events, parsed, until the stream ends (or `[DONE]`). Every provider
    /// puts the event's type in its data, so `event:` lines aren't needed.
    /// Cancelling the stream's consumer closes the connection.
    func events(_ request: URLRequest, api: some AIErrorClassifying, model: String?) -> AsyncThrowingStream<JSONValue, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let bytes = try await open(request, api: api, model: model)
                    let decoder = JSONDecoder()
                    do {
                        for try await line in bytes.lines {
                            guard line.hasPrefix("data:") else { continue }
                            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                            if payload == "[DONE]" { break }
                            guard let data = payload.data(using: .utf8),
                                  let event = try? decoder.decode(JSONValue.self, from: data)
                            else { continue }
                            continuation.yield(event)
                        }
                    } catch {
                        throw transportFailure(error, identity: api.identity)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The answer's bytes once it's a 2xx, after retrying what's worth it.
    func open(_ request: URLRequest, api: some AIErrorClassifying, model: String?) async throws -> URLSession.AsyncBytes {
        var attempt = 0
        while true {
            try Task.checkCancellation()
            let bytes: URLSession.AsyncBytes
            let response: URLResponse
            do {
                (bytes, response) = try await session.bytes(for: request)
            } catch {
                throw transportFailure(error, identity: api.identity)
            }
            guard let http = response as? HTTPURLResponse else {
                throw api.identity.failure(.other("The answer wasn't HTTP."))
            }
            if (200..<300).contains(http.statusCode) { return bytes }

            let error = await Self.error(http, bytes: bytes)
            if attempt < maxRetries, api.isRetryable(error) {
                let wait = error.retryAfter ?? Self.backoff(attempt)
                if wait <= maxRetryDelay {
                    attempt += 1
                    try await sleep(wait)
                    continue
                }
            }
            throw api.failure(for: error, model: model)
        }
    }

    /// 1 s, then 2 s, when the provider doesn't say how long to wait.
    static func backoff(_ attempt: Int) -> Duration {
        .seconds(1 << min(attempt, 4))
    }

    static func error(_ response: HTTPURLResponse, bytes: URLSession.AsyncBytes) async -> AIHTTPError {
        var data = Data()
        do {
            for try await byte in bytes {
                data.append(byte)
                if data.count >= errorBodyLimit { break }
            }
        } catch {}
        return AIHTTPError(
            status: response.statusCode,
            body: try? JSONDecoder().decode(JSONValue.self, from: data),
            text: String(decoding: data, as: UTF8.self),
            retryAfter: AIHTTPError.retryAfter(response)
        )
    }

    /// A failure to connect or to keep receiving, as the reader should
    /// hear it. Cancellation stays cancellation.
    func transportFailure(_ error: Error, identity: AIProviderIdentity) -> Error {
        if error is CancellationError || error is CatchUpModelError { return error }
        guard let urlError = error as? URLError else {
            return identity.failure(.other(AIProviderFailure.trimmed(error.localizedDescription)))
        }
        switch urlError.code {
        case .cancelled:
            return CancellationError()
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff, .callIsActive:
            return identity.failure(identity.isCustomServer ? .unreachable : .offline)
        case .cannotFindHost, .dnsLookupFailed:
            return identity.failure(identity.isCustomServer ? .unreachable : .offline)
        case .cannotConnectToHost:
            return identity.failure(.unreachable)
        case .timedOut:
            return identity.failure(.timedOut)
        case .appTransportSecurityRequiresSecureConnection:
            return identity.failure(.other("This address needs https. Over http, use localhost, a .local name or an IP address."))
        default:
            return identity.failure(.other(AIProviderFailure.trimmed(urlError.localizedDescription)))
        }
    }
}
