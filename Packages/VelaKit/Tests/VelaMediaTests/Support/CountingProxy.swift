// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Network

/// A local HTTP CONNECT proxy that counts the bytes each tunnel carries, to
/// measure what a web view really transfers (TLS included), however much
/// of it a page's own timing APIs can see.
final class CountingProxy: @unchecked Sendable {
    struct HostTotal: Sendable {
        var host: String
        var tunnels: Int
        var bytesIn: Int
        var bytesOut: Int
    }

    private let queue = DispatchQueue(label: "vela.counting-proxy")
    private let listener: NWListener
    // Guarded by `queue`.
    private var totals: [String: HostTotal] = [:]
    private var connections: [NWConnection] = []

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
    }

    /// Starts listening; returns the endpoint to configure as the proxy.
    func start() async throws -> NWEndpoint {
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        let port: NWEndpoint.Port = try await withCheckedThrowingContinuation { continuation in
            let resumed = Box(false)
            listener.stateUpdateHandler = { [listener] state in
                guard !resumed.value else { return }
                switch state {
                case .ready:
                    resumed.value = true
                    continuation.resume(returning: listener.port ?? 0)
                case .failed(let error):
                    resumed.value = true
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
        return .hostPort(host: "127.0.0.1", port: port)
    }

    func stop() {
        queue.sync {
            listener.cancel()
            connections.forEach { $0.cancel() }
            connections.removeAll()
        }
    }

    /// Per host, most bytes first.
    var hostTotals: [HostTotal] {
        queue.sync { totals.values.sorted { $0.bytesIn + $0.bytesOut > $1.bytesIn + $1.bytesOut } }
    }

    var bytesIn: Int { hostTotals.reduce(0) { $0 + $1.bytesIn } }
    var bytesOut: Int { hostTotals.reduce(0) { $0 + $1.bytesOut } }
    var tunnels: Int { hostTotals.reduce(0) { $0 + $1.tunnels } }

    // MARK: - Tunnels

    private final class Box<T>: @unchecked Sendable {
        var value: T
        init(_ value: T) { self.value = value }
    }

    private func accept(_ client: NWConnection) {
        connections.append(client)
        client.start(queue: queue)
        readRequest(client, buffer: Data())
    }

    private func readRequest(_ client: NWConnection, buffer: Data) {
        client.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            guard let end = buffer.range(of: Data("\r\n\r\n".utf8)) else {
                if error == nil, !isComplete, buffer.count < 64 * 1024 { self.readRequest(client, buffer: buffer) } else { client.cancel() }
                return
            }
            let head = String(decoding: buffer[..<end.lowerBound], as: UTF8.self)
            let early = buffer[end.upperBound...]
            let parts = head.split(separator: "\r\n").first?.split(separator: " ") ?? []
            guard parts.count >= 2, parts[0] == "CONNECT",
                  let colon = parts[1].lastIndex(of: ":"),
                  let port = NWEndpoint.Port(String(parts[1][parts[1].index(after: colon)...]))
            else {
                client.send(content: Data("HTTP/1.1 405 Method Not Allowed\r\nContent-Length: 0\r\n\r\n".utf8),
                            completion: .contentProcessed { _ in client.cancel() })
                return
            }
            let host = String(parts[1][..<colon])
            self.open(host: host, port: port, client: client, early: Data(early))
        }
    }

    private func open(host: String, port: NWEndpoint.Port, client: NWConnection, early: Data) {
        let upstream = NWConnection(host: NWEndpoint.Host(host), port: port, using: .tcp)
        connections.append(upstream)
        totals[host, default: HostTotal(host: host, tunnels: 0, bytesIn: 0, bytesOut: 0)].tunnels += 1
        upstream.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                client.send(content: Data("HTTP/1.1 200 Connection Established\r\n\r\n".utf8), completion: .contentProcessed { _ in
                    if !early.isEmpty {
                        self.totals[host]?.bytesOut += early.count
                        upstream.send(content: early, completion: .idempotent)
                    }
                    self.pipe(from: client, to: upstream, host: host, inbound: false)
                    self.pipe(from: upstream, to: client, host: host, inbound: true)
                })
            case .failed, .cancelled:
                client.cancel()
            default:
                break
            }
        }
        upstream.start(queue: queue)
    }

    private func pipe(from source: NWConnection, to destination: NWConnection, host: String, inbound: Bool) {
        source.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                if inbound { self.totals[host]?.bytesIn += data.count } else { self.totals[host]?.bytesOut += data.count }
                destination.send(content: data, completion: .contentProcessed { [weak self] sendError in
                    guard sendError == nil else {
                        source.cancel()
                        destination.cancel()
                        return
                    }
                    if isComplete || error != nil {
                        destination.cancel()
                    } else {
                        self?.pipe(from: source, to: destination, host: host, inbound: inbound)
                    }
                })
            } else if isComplete || error != nil {
                source.cancel()
                destination.cancel()
            } else {
                self.pipe(from: source, to: destination, host: host, inbound: inbound)
            }
        }
    }
}
