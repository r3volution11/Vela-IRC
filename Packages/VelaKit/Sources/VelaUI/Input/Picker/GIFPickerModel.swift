// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Observation
import VelaMedia
import VelaStore

/// The GIFs tab's results: trending with no search, a search once the
/// field has paused (``debounce``) or Return is pressed, more pages as the
/// grid is scrolled to its end, and what went wrong.
///
/// Made when the GIFs tab is first shown; ``stop()`` cancels whatever is
/// loading when the tab is left or the picker closes.
@MainActor
@Observable
final class GIFPickerModel {
    enum Status: Equatable {
        case loading
        case results
        /// Nothing found.
        case empty
        case failed(GIFSearchError)
        /// GIFs can't be searched as set up (no key).
        case unavailable(GIFSearchSetup.Problem)
    }

    /// How long typing pauses before the search goes out.
    static let debounce: Duration = .milliseconds(400)
    /// Shorter searches show trending instead.
    static let minimumSearchLength = 2

    let setup: GIFSearchSetup
    let rating: GIFContentRating

    private(set) var results: [GIFSearchResult] = []
    private(set) var status: Status
    /// What `results` are for.
    private(set) var shownQuery: GIFQuery = .trending
    private(set) var isLoadingMore = false
    /// Loading the next page failed; the results so far stay.
    private(set) var moreError: GIFSearchError?
    /// Try again waits until then after the service said it's busy.
    private(set) var retryAvailableAt: Date?
    /// The result picked with the arrow keys, by index.
    var selection: Int?

    @ObservationIgnored private let client: GIFSearchClient?
    @ObservationIgnored private var next: GIFPageToken?
    /// The query last asked for (shown, loading or waiting for the pause).
    @ObservationIgnored private(set) var wantedQuery: GIFQuery = .trending
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var loadingQuery: GIFQuery?
    @ObservationIgnored private var moreTask: Task<Void, Never>?
    @ObservationIgnored private var retryTimer: Task<Void, Never>?

    init(setup: GIFSearchSetup, rating: GIFRating, services: GIFSearchServices) {
        self.setup = setup
        self.rating = Self.contentRating(rating)
        self.client = services.client(for: setup)
        self.status = setup.problem.map(Status.unavailable) ?? .loading
    }

    static func contentRating(_ rating: GIFRating) -> GIFContentRating {
        switch rating {
        case .g: .g
        case .pg: .pg
        case .pg13: .pg13
        case .r: .r
        }
    }

    /// What the field's text asks for: trending when it's shorter than
    /// ``minimumSearchLength``.
    static func query(for text: String) -> GIFQuery {
        let query = GIFQuery(text: text)
        guard let search = query.text, search.count >= minimumSearchLength else { return .trending }
        return query
    }

    var provider: any GIFSearchProvider { setup.provider }

    var selectedResult: GIFSearchResult? {
        selection.flatMap { results.indices.contains($0) ? results[$0] : nil }
    }

    /// A search is waiting for the pause.
    var isWaitingForPause: Bool { debounceTask != nil }

    // MARK: Asking

    /// The tab was shown with `text` in the field: no pause.
    func show(text: String) {
        run(Self.query(for: text))
    }

    /// The field changed: the search goes out after a pause, unless the
    /// text changes again first.
    func textChanged(_ text: String) {
        let query = Self.query(for: text)
        debounceTask?.cancel()
        debounceTask = nil
        guard query != wantedQuery else { return }
        wantedQuery = query
        if query == .trending {
            // Back to trending: likely in memory, and no reason to wait.
            run(query)
            return
        }
        debounceTask = Task { [weak self] in
            do { try await Task.sleep(for: Self.debounce) } catch { return }
            guard let self, !Task.isCancelled else { return }
            self.debounceTask = nil
            self.run(query)
        }
    }

    /// Return: a search that's waiting goes out now (true). Otherwise
    /// false, and Return picks the selected GIF.
    func submit(text: String) -> Bool {
        let query = Self.query(for: text)
        guard debounceTask != nil || query != shownQuery else { return false }
        run(query)
        return true
    }

    /// Try again, after an error.
    func retry() {
        if moreError != nil, status == .results {
            moreError = nil
            loadMore(force: true)
            return
        }
        run(wantedQuery, retry: true)
    }

    /// The result at `index` came into view: the next page loads when it's
    /// in the last row.
    func resultAppeared(at index: Int, columns: Int) {
        guard index >= results.count - max(1, columns) else { return }
        loadMore(force: false)
    }

    /// Stops loading: the tab was left or the picker closed.
    func stop() {
        debounceTask?.cancel()
        debounceTask = nil
        loadTask?.cancel()
        loadTask = nil
        loadingQuery = nil
        moreTask?.cancel()
        moreTask = nil
        retryTimer?.cancel()
        retryTimer = nil
        isLoadingMore = false
    }

    // MARK: Moving

    /// Moves the selection by a key in a grid of `columns`.
    func move(_ move: GridMove, columns: Int) {
        guard !results.isEmpty else { return }
        guard let current = selection, results.indices.contains(current) else {
            selection = 0
            return
        }
        let target: Int = switch move {
        case .left: current - 1
        case .right: current + 1
        case .up: current - columns
        case .down: current + columns
        }
        if results.indices.contains(target) {
            selection = target
        } else if move == .down, current / columns < (results.count - 1) / columns {
            // Into a shorter last row.
            selection = results.count - 1
        }
    }

    // MARK: Loading

    private func run(_ query: GIFQuery, retry: Bool = false) {
        debounceTask?.cancel()
        debounceTask = nil
        wantedQuery = query
        guard let client else { return }
        if !retry {
            // Already shown, or already on its way.
            if loadTask == nil, query == shownQuery, status == .results || status == .empty { return }
            if loadTask != nil, query == loadingQuery { return }
        }
        loadingQuery = query
        loadTask?.cancel()
        moreTask?.cancel()
        moreTask = nil
        isLoadingMore = false
        moreError = nil
        status = .loading
        let rating = rating
        loadTask = Task { [weak self] in
            do {
                let page = try await client.page(query, rating: rating, retry: retry)
                guard !Task.isCancelled, let self else { return }
                self.loadTask = nil
                self.shownQuery = query
                self.results = page.results
                self.next = page.next
                self.selection = nil
                self.status = page.results.isEmpty ? .empty : .results
            } catch let error as GIFSearchError {
                guard !Task.isCancelled, let self else { return }
                self.loadTask = nil
                self.shownQuery = query
                self.results = []
                self.next = nil
                self.selection = nil
                self.status = .failed(error)
                await self.holdRetry(after: error, client: client)
            } catch {
                // Cancelled: a newer query took over.
            }
        }
    }

    private func loadMore(force: Bool) {
        guard let client, let next, status == .results, !isLoadingMore, force || moreError == nil else { return }
        isLoadingMore = true
        let query = shownQuery
        let rating = rating
        moreTask = Task { [weak self] in
            do {
                let page = try await client.page(query, page: next, rating: rating)
                guard !Task.isCancelled, let self, self.shownQuery == query else { return }
                self.results += page.results
                self.next = page.next
                self.isLoadingMore = false
                self.moreTask = nil
            } catch let error as GIFSearchError {
                guard !Task.isCancelled, let self else { return }
                self.moreError = error
                self.isLoadingMore = false
                self.moreTask = nil
                await self.holdRetry(after: error, client: client)
            } catch {
                guard let self else { return }
                self.isLoadingMore = false
            }
        }
    }

    /// Greys out Try again until the service may be asked again.
    private func holdRetry(after error: GIFSearchError, client: GIFSearchClient) async {
        guard error == .rateLimited, let at = await client.retryAllowedAt() else { return }
        retryAvailableAt = at
        retryTimer?.cancel()
        retryTimer = Task { [weak self] in
            let delay = max(0, at.timeIntervalSinceNow)
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            self?.retryAvailableAt = nil
        }
    }
}
