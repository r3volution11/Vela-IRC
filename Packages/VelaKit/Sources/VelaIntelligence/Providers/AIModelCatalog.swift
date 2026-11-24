// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Observation
import VelaStore

/// Each provider's model list: fetched when you ask (Test, Refresh), when
/// a key changes, and when Settings → AI Providers shows a provider whose
/// list is missing or more than a day old. Until then, menus offer Vela's
/// recommended models for the provider. Lists are kept in a small cache
/// file (model names and limits only, nothing about you), so menus have
/// them at the next launch without asking the provider again. Nothing is
/// fetched for a provider you haven't added.
@Observable
public final class AIModelCatalog {
    public enum State: Equatable, Sendable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    /// Fetched lists, by provider id.
    public private(set) var lists: [String: [AIModelInfo]] = [:]
    /// How each provider's list is doing, by provider id.
    public private(set) var states: [String: State] = [:]

    @ObservationIgnored private let cacheURL: URL?
    @ObservationIgnored private var cache: [String: CachedList] = [:]
    @ObservationIgnored private var cacheLoaded = false
    @ObservationIgnored private var tasks: [String: Task<Result<[AIModelInfo], AIProviderFailure>, Never>] = [:]

    /// How long a list is fresh enough not to fetch again on its own.
    static let freshness: TimeInterval = 24 * 60 * 60

    /// One provider's list as the cache file keeps it, with what it was
    /// fetched for: a list for another kind or address is stale.
    struct CachedList: Codable, Equatable {
        var kind: AIProviderKind
        var baseURL: String?
        var fetched: Date
        var models: [AIModelInfo]
    }

    /// - Parameter cacheURL: Where lists are kept between launches; nil
    ///   keeps them in memory only (tests, demo mode).
    public init(cacheURL: URL? = nil) {
        self.cacheURL = cacheURL
    }

    /// The models to offer for `entry`: its fetched list, or the
    /// recommended ones until there is one.
    public func models(for entry: AIProviderEntry) -> [AIModelInfo] {
        if let list = fetched(for: entry), !list.isEmpty { return list }
        return entry.kind.recommendedModels
    }

    /// The list fetched this session, else the one in the cache file when
    /// it was fetched for the same kind and address. Reading the file
    /// changes nothing observed, so it's safe while a view is drawn.
    private func fetched(for entry: AIProviderEntry) -> [AIModelInfo]? {
        if let list = lists[entry.id] { return list }
        loadCacheIfNeeded()
        guard let cached = cache[entry.id], cached.kind == entry.kind, cached.baseURL == entry.baseURL else { return nil }
        return cached.models
    }

    /// What's known about one model: from the fetched list, else Vela's
    /// recommended ones.
    public func info(for entry: AIProviderEntry, modelID: String) -> AIModelInfo? {
        fetched(for: entry)?.first { $0.id == modelID } ?? entry.kind.recommendedModels.first { $0.id == modelID }
    }

    public func state(for providerID: String) -> State {
        states[providerID] ?? .idle
    }

    /// Fetches `entry`'s list with `api` (off the main actor), replacing
    /// the one kept. A fetch already under way is shared.
    @discardableResult
    func refresh(_ entry: AIProviderEntry, api: (any AIProviderAPI)?) async -> Result<[AIModelInfo], AIProviderFailure> {
        if let running = tasks[entry.id] { return await running.value }
        guard let api else {
            let failure = AIProviderFailure(providerID: entry.id, providerName: entry.name, reason: .unreachable)
            states[entry.id] = .failed(failure.message)
            return .failure(failure)
        }
        states[entry.id] = .loading
        let task = Task { await Self.fetch(api) }
        tasks[entry.id] = task
        let result = await task.value
        tasks[entry.id] = nil
        switch result {
        case .success(let models):
            lists[entry.id] = models
            states[entry.id] = .loaded
            // Read the file first, so saving keeps the other lists.
            loadCacheIfNeeded()
            cache[entry.id] = CachedList(kind: entry.kind, baseURL: entry.baseURL, fetched: Date(), models: models)
            saveCache()
        case .failure(let failure):
            states[entry.id] = .failed(failure.message)
        }
        return result
    }

    /// Whether `entry`'s list should be fetched on its own: there's none,
    /// it's for another address, or it's more than a day old.
    func isStale(_ entry: AIProviderEntry, now: Date = Date()) -> Bool {
        loadCacheIfNeeded()
        guard states[entry.id] != .loading else { return false }
        guard let cached = cache[entry.id], cached.kind == entry.kind, cached.baseURL == entry.baseURL else { return true }
        return now.timeIntervalSince(cached.fetched) > Self.freshness
    }

    /// Forgets `providerID`'s list: its key or address changed, or it was
    /// removed.
    public func forget(_ providerID: String) {
        tasks.removeValue(forKey: providerID)?.cancel()
        lists[providerID] = nil
        states[providerID] = nil
        if cache.removeValue(forKey: providerID) != nil { saveCache() }
    }

    /// Keeps `models` as `entry`'s list, fetched just now by someone else
    /// (the setup sheet's check, or finding a server on this Mac).
    func remember(_ models: [AIModelInfo], for entry: AIProviderEntry) {
        loadCacheIfNeeded()
        lists[entry.id] = models
        states[entry.id] = .loaded
        cache[entry.id] = CachedList(kind: entry.kind, baseURL: entry.baseURL, fetched: Date(), models: models)
        saveCache()
    }

    @concurrent
    nonisolated static func fetch(_ api: any AIProviderAPI) async -> Result<[AIModelInfo], AIProviderFailure> {
        do {
            return .success(try await api.listModels())
        } catch let CatchUpModelError.provider(failure) {
            return .failure(failure)
        } catch is CancellationError {
            return .failure(AIProviderFailure(providerID: api.identity.id, providerName: api.identity.name, reason: .other("Cancelled.")))
        } catch {
            return .failure(AIProviderFailure(providerID: api.identity.id, providerName: api.identity.name, reason: .other(AIProviderFailure.trimmed(error.localizedDescription))))
        }
    }

    // MARK: Cache file

    private func loadCacheIfNeeded() {
        guard !cacheLoaded else { return }
        cacheLoaded = true
        guard let cacheURL, let data = try? Data(contentsOf: cacheURL),
              let decoded = try? JSONDecoder().decode([String: CachedList].self, from: data)
        else { return }
        cache = decoded
    }

    private func saveCache() {
        guard let cacheURL else { return }
        let snapshot = cache
        Task.detached(priority: .utility) {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            guard let data = try? encoder.encode(snapshot) else { return }
            try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: cacheURL, options: .atomic)
        }
    }
}
