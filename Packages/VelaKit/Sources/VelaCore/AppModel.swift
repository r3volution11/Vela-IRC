// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import Foundation
import Network
import Observation
import VelaFoundation
import VelaIRC
import VelaMedia
import VelaStore

/// Secrets entered in the network editor. Stored in the Keychain, never in files.
nonisolated public struct NetworkSecrets: Sendable, Equatable {
    public var serverPassword: String?
    public var saslPassword: String?
    public var nickServPassword: String?

    public init(serverPassword: String? = nil, saslPassword: String? = nil, nickServPassword: String? = nil) {
        self.serverPassword = serverPassword
        self.saslPassword = saslPassword
        self.nickServPassword = nickServPassword
    }
}

/// The root model: networks, selection and app-wide services.
@Observable
public final class AppModel: SessionHost {
    public let settings: SettingsStore
    public let networkStore: NetworkConfigStore
    public let database: VelaDatabase?
    public let previewService: LinkPreviewService
    /// Plain-text chat logs (`logging.*`); see AppModel+ChatLogs.swift.
    public let chatLogs: ChatLogService
    public let keychain: Keychain
    public let isDemo: Bool

    public private(set) var sessions: [NetworkSession] = []
    public private(set) var selectedBufferID: BufferID?
    /// The buffer last selected on each network, so going back to a network
    /// (its tab, ⌃⌘[ / ⌃⌘]) returns to where you were there.
    @ObservationIgnored private var lastSelectedOnNetwork: [UUID: BufferID] = [:]
    public private(set) var lastError: String?
    /// True once ``start()`` has restored saved networks and buffers, with
    /// each buffer's recent history (at once in demo mode). Siri and
    /// Shortcuts wait for it with ``ready()``.
    public private(set) var isReady = false
    /// The latest request to bring a buffer on screen from outside the
    /// window (Siri, Shortcuts, Spotlight). The scene layer selects it,
    /// activates Vela and reopens the main window if it was closed.
    public private(set) var showRequest: ShowRequest?
    /// Called when you send a message from the composer (not a command).
    /// The scene layer donates it to Siri so it learns where you talk.
    @ObservationIgnored public var onComposerMessage: ((BufferModel, NetworkSession) -> Void)?
    /// Spotlight's index of messages (`intelligence.spotlightMessages`):
    /// hears about saved messages arriving and going away. Nil while it's
    /// off. See SavedMessages.swift.
    @ObservationIgnored public weak var savedMessagesObserver: (any SavedMessagesObserver)?
    /// Whether the Dock icon shows the offline mark: `dock.showOffline` is
    /// on and a network Vela means to be connected to has been offline for
    /// longer than the grace period. The scene layer's `DockIconController`
    /// draws it. Always false in demo mode. See AppModel+Dock.swift.
    public internal(set) var showsOfflineMark = false
    /// The Dock badge, offline mark and bounce bookkeeping (AppModel+Dock.swift).
    @ObservationIgnored var dock = DockState()
    /// Channels you removed or hid and conversations you closed, newest
    /// first, at most ``recentlyClosedLimit``. Kept in memory only: quitting
    /// forgets them. See AppModel+RecentlyClosed.swift.
    public internal(set) var recentlyClosed: [ClosedBuffer] = []
    /// The main window's undo manager, set by the scene layer. Leaving,
    /// removing and closing are registered there, on the same stack as
    /// typing in the message box, so ⌘Z puts things back.
    @ObservationIgnored public weak var undoManager: UndoManager?
    /// The undo manager's target for each buffer's undo and redo, so they
    /// can be dropped when the buffer comes back some other way.
    @ObservationIgnored var closeUndoTargets: [BufferID: CloseUndoTarget] = [:]

    /// What history is saved on disk: messages, reactions, link previews.
    /// Read from the database when the model is made (a few index lookups)
    /// and refreshed by ``refreshSavedHistory()``. With saving off, saved
    /// messages still load (``HistoryStorage/loadOnly``). See
    /// AppModel+History.swift.
    public internal(set) var savedHistory: SavedHistory
    /// Whether the link preview cache in the database is used (`history.save`).
    @ObservationIgnored let previewDiskCache: PreviewDiskCacheSwitch
    /// Turns the image cache on disk on or off with `history.save`. That
    /// cache is shared by the whole process, so tests, which make many
    /// models side by side, swap this to watch their own.
    @ObservationIgnored var setImageDiskCache: (Bool) -> Void = { ImageLoader.setDiskCacheEnabled($0) }
    /// Facts kept between launches: the version What's New last showed,
    /// one-time migrations and the notices they leave.
    public let launchRecord: LaunchRecord
    /// What Siri and Shortcuts actions wait with while networks connect.
    /// Tests swap in a clock they move themselves.
    @ObservationIgnored var actionClock = ActionClock.continuous
    /// Whether Vela had run on this Mac before this launch (its database
    /// was already there). What's New isn't shown to a new install.
    public internal(set) var isExistingInstall = false

    /// Whether the main window is key; drives unread counting.
    public var isWindowActive = true {
        didSet {
            guard isWindowActive != oldValue, let buffer = selectedBuffer, let session = selectedSession else { return }
            if isWindowActive { prepareUnreadMarker(buffer) }
            // Focusing reads what arrived meanwhile. Losing focus records how
            // far the reader got, so the "New" marker goes above the next line.
            session.markRead(buffer)
        }
    }

    @ObservationIgnored private let notifier: Notifier
    @ObservationIgnored private var pathMonitor: NWPathMonitor?
    /// Sleep and wake (NSWorkspace), and app activation.
    @ObservationIgnored private var systemObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var sessionsConnectedBeforeSleep: Set<UUID> = []
    @ObservationIgnored private var started = false
    @ObservationIgnored private var readyWaiters: [CheckedContinuation<Void, Never>] = []
    /// `siteRules` parsed from the settings value it was parsed from.
    @ObservationIgnored private var siteRulesCache: (source: [String: JSONValue], rules: SiteRules)?

    public init(
        settings: SettingsStore,
        networkStore: NetworkConfigStore,
        database: VelaDatabase?,
        keychain: Keychain = .shared,
        previewService: LinkPreviewService? = nil,
        notifier: Notifier? = nil,
        launchRecord: LaunchRecord? = nil,
        isDemo: Bool = false
    ) {
        self.settings = settings
        self.networkStore = networkStore
        self.database = database
        self.keychain = keychain
        self.isDemo = isDemo
        self.launchRecord = launchRecord ?? .inMemory()
        self.savedHistory = (try? database?.savedHistoryNow()) ?? SavedHistory()
        let previewDiskCache = PreviewDiskCacheSwitch(isOn: settings[.historySave])
        self.previewDiskCache = previewDiskCache
        self.previewService = previewService ?? LinkPreviewService(
            cache: database.map { DatabasePreviewCache(database: $0, diskCache: previewDiskCache) }
        )
        self.notifier = notifier ?? (isDemo ? SilentNotifier() : UserNotificationNotifier())
        // Logs go next to settings.json by default: Vela's data folder, or
        // demo mode's temporary one (where nothing is logged anyway).
        self.chatLogs = ChatLogService(
            settings: settings,
            defaultFolder: settings.fileURL.deletingLastPathComponent().appending(path: "Logs", directoryHint: .isDirectory),
            preferences: isDemo ? InMemoryChatLogPreferences() : UserDefaultsChatLogPreferences(),
            isDemo: isDemo
        )
    }

    /// The production configuration rooted in Application Support.
    public static func live() -> AppModel {
        // Before anything creates them: has Vela run on this Mac before?
        let isExistingInstall = [AppPaths.databaseURL, AppPaths.networksURL, AppPaths.settingsURL]
            .contains { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
        let database: VelaDatabase?
        var startupError: String?
        do {
            database = try VelaDatabase(url: AppPaths.databaseURL)
        } catch {
            database = nil
            startupError = "Couldn't open the message database: \(error.localizedDescription)"
        }
        let networkStore = NetworkConfigStore(fileURL: AppPaths.networksURL)
        do { try networkStore.load() } catch { startupError = "Couldn't read networks.json: \(error.localizedDescription)" }
        let settings = SettingsStore(fileURL: AppPaths.settingsURL)
        settings.applyMigrations()
        // Upgraders keep saving history (history.save), before anything
        // reads the setting.
        let launchRecord = LaunchRecord.userDefaults()
        let savedHistory = database.flatMap { try? $0.savedHistoryNow() }
        HistorySaveMigration.run(settings: settings, savedHistory: savedHistory, record: launchRecord, version: appVersion)
        // Vela 1.0's Modern Chat spacing (2 and 6) moves to the preset's
        // new 4 and 12, once, if it's still exactly that.
        ModernChatSpacingMigration.run(settings: settings, record: launchRecord, version: appVersion)
        // Before any image loads (start() keeps it in step afterwards).
        ImageLoader.setDiskCacheEnabled(settings[.historySave])
        let model = AppModel(
            settings: settings,
            networkStore: networkStore,
            database: database,
            launchRecord: launchRecord
        )
        model.isExistingInstall = isExistingInstall
        model.lastError = startupError
        return model
    }

    /// Offline sample content for screenshots, SwiftUI previews and UI work.
    ///
    /// - Parameters:
    ///   - networks: false starts with no networks, as on first launch (the
    ///     welcome screen); `--no-networks` in demo mode.
    ///   - selectsChannel: false leaves nothing selected (the "Pick a
    ///     conversation" screen); `--no-selection` in demo mode.
    public static func demo(networks: Bool = true, selectsChannel: Bool = true) -> AppModel {
        DemoScratch.removeStale()
        let root = DemoScratch.makeDirectory(prefix: "VelaDemo-")
        let model = AppModel(
            settings: SettingsStore(fileURL: root.appendingPathComponent("settings.json")),
            networkStore: NetworkConfigStore(fileURL: root.appendingPathComponent("networks.json")),
            database: nil,
            isDemo: true
        )
        if networks { DemoContent.populate(model, selectsChannel: selectsChannel) }
        return model
    }

    /// Starts sessions and system observers. Safe to call more than once.
    public func start() {
        guard !started else { return }
        started = true
        // Parse the bundled adult-site list now, off the main actor, so the
        // first preview doesn't pay for it (only if the filter is on; it
        // loads on first use otherwise).
        if settings[.mediaFilterAdultSites] {
            Task.detached(priority: .utility) { AdultSiteList.warmUp() }
        }
        guard !isDemo else {
            markReady()
            return
        }

        for config in networkStore.networks {
            let session = makeSession(for: config)
            sessions.append(session)
        }
        Task {
            for session in sessions { await session.restoreBuffers() }
            restoreSelection()
            for session in sessions where session.config.autoConnect && !isOrphanedChild(session) {
                session.connect()
            }
            // Siri and Shortcuts count what's unread from each buffer's
            // restored history (live counts start at zero), so readiness
            // waits for it too.
            for session in sessions { await session.recentHistoryLoaded() }
            markReady()
        }
        observeSystem()
        observeDockSettings()
        observeHistorySetting()
        chatLogs.start(networkIDs: Set(networkStore.networks.map(\.id)))
        updateDock()
        pruneHistoryIfNeeded()
        prunePreviewCache()
    }

    /// For a script reading networks or conversations, which Cocoa
    /// scripting can't wait for: starts Vela if it hasn't been (a script
    /// can launch it before the main window appears), and while it's still
    /// launching, restores each network's channels and conversations from
    /// the store now. Their history and unread counts arrive as usual. Does
    /// nothing once Vela is ready.
    public func restoreConversationsNow() {
        guard !isReady else { return }
        start()
        for session in sessions { session.restoreBuffersNow() }
    }

    /// Starts Vela if it hasn't been (Siri and Shortcuts can run before the
    /// main window appears) and waits until saved networks and buffers are
    /// restored, and each buffer's recent lines have loaded from the
    /// message store. Connections may still be in progress.
    public func ready() async {
        start()
        guard !isReady else { return }
        await withCheckedContinuation { readyWaiters.append($0) }
    }

    private func markReady() {
        guard !isReady else { return }
        isReady = true
        let waiters = readyWaiters
        readyWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }

    /// Asks the scene layer to show `bufferID`: select it, activate Vela,
    /// and open the main window if it's closed. A `draft` replaces the
    /// buffer's unsent text (Siri's "draft a message"), or with
    /// `appendingDraft` goes after it (a `vela://` link never throws away
    /// what you were typing). With a `line`, the message list scrolls to
    /// that message, loading older history to find it if need be.
    public func requestShow(_ bufferID: BufferID, draft: String? = nil, appendingDraft: Bool = false, line: LineReference? = nil) {
        showRequest = ShowRequest(bufferID: bufferID, draft: draft, appendsDraft: appendingDraft, line: line)
    }

    // MARK: SessionHost

    public var behavior: SessionBehavior {
        var behavior = SessionBehavior()
        behavior.autoReconnect = settings[.connectionAutoReconnect]
        behavior.sendTypingIndicators = settings[.inputSendTypingIndicators]
        behavior.highlightWords = settings[.highlightWords]
        behavior.scrollbackInMemory = max(200, settings[.chatScrollbackInMemory])
        behavior.banMaskStyle = settings[.moderationBanMask]
        behavior.defaultKickReason = settings[.moderationKickReason]
        return behavior
    }

    public func clientConfig(for session: NetworkSession) -> IRCClientConfig {
        // Bouncer child networks borrow the parent's connection details and credentials.
        let base = session.config.parentNetworkID.flatMap { id in networkStore.networks.first { $0.id == id } } ?? session.config
        var config = IRCClientConfig(
            host: base.host,
            port: base.port,
            useTLS: base.useTLS,
            nick: base.nick
        )
        config.allowInvalidCertificates = base.allowInvalidCertificates
        config.alternateNicks = base.alternateNicks
        config.username = base.username.isEmpty ? base.nick : base.username
        config.realname = base.realname.isEmpty ? base.nick : base.realname
        if base.hasServerPassword {
            config.serverPassword = keychain.secret(account: Keychain.account(networkID: base.id, purpose: .serverPassword))
        }
        switch base.saslKind {
        case .plain:
            if let password = keychain.secret(account: Keychain.account(networkID: base.id, purpose: .saslPassword)) {
                config.sasl = .plain(account: base.saslAccount ?? base.nick, password: password)
            }
        case .external:
            config.sasl = .external
        case .none:
            break
        }
        if let ref = base.clientCertificateRef, let identity = keychain.identity(persistentRef: ref) {
            config.clientIdentity = ClientIdentity(identity: identity)
        }
        config.bouncerNetworkID = session.config.bouncerNetworkID
        config.versionReply = "Vela \(Self.appVersion) on macOS — https://github.com/r3volution11/Vela-IRC"
        return config
    }

    public func isBufferVisible(_ id: BufferID) -> Bool {
        isWindowActive && selectedBufferID == id
    }

    public func activeBuffer(in session: NetworkSession) -> BufferModel? {
        guard let id = selectedBufferID, id.networkID == session.id else { return nil }
        return session.buffer(id: id)
    }

    public func session(_ session: NetworkSession, didReceiveNotable line: ChatLine, in buffer: BufferModel) {
        requestDockAttention(for: line, in: buffer)
        guard !isBufferVisible(buffer.id) || !NSApp.isActive else { return }
        let isQuery = buffer.kind == .query
        if line.isHighlight && !settings[.notifyHighlights] { return }
        if isQuery && !line.isHighlight && !settings[.notifyPrivateMessages] { return }
        let title = isQuery ? (line.nick ?? buffer.name) : "\(line.nick ?? "") in \(buffer.name)"
        let body = line.kind == .action ? "• \(line.nick ?? "") \(line.text)" : line.text
        notifier.post(
            title: title,
            subtitle: session.displayName,
            body: IRCFormatting.strip(body),
            bufferID: buffer.id,
            lineID: line.id,
            playSound: settings[.notifySound]
        )
    }

    public func session(_ session: NetworkSession, didUpdateBouncerNetworks networks: [BouncerNetwork]) {
        let existing = networkStore.networks.filter { $0.parentNetworkID == session.id }
        // Add or update children.
        for network in networks {
            if var child = existing.first(where: { $0.bouncerNetworkID == network.id }) {
                if child.name != network.name {
                    child.name = network.name
                    networkStore.upsert(child)
                    self.session(for: child.id)?.updateConfig(child)
                }
                continue
            }
            var child = session.config
            child.id = UUID()
            child.name = network.name
            child.parentNetworkID = session.id
            child.bouncerNetworkID = network.id
            child.autoJoin = []
            child.performCommands = []
            child.pendingParts = []
            child.pendingDetaches = []
            child.sortOrder = session.config.sortOrder
            child.createdAt = Date()
            child.modifiedAt = Date()
            networkStore.upsert(child)
            let childSession = makeSession(for: child)
            sessions.append(childSession)
            childSession.connect()
        }
        // Remove children the bouncer no longer has.
        let liveIDs = Set(networks.map(\.id))
        for child in existing where !liveIDs.contains(child.bouncerNetworkID ?? "") {
            removeNetwork(id: child.id)
        }
        sortSessions()
    }

    public func sessionDidChangeConfig(_ session: NetworkSession) {
        networkStore.upsert(keepingPosition(session.config))
    }

    /// `config` with the position it has in the store, which only the
    /// network order methods change.
    private func keepingPosition(_ config: NetworkConfig) -> NetworkConfig {
        var config = config
        if let stored = networkStore.network(id: config.id) { config.sortOrder = stored.sortOrder }
        return config
    }

    public func sessionDidChangeUnreadCounts(_ session: NetworkSession) {
        updateDockBadge()
    }

    public func sessionDidChangeConnection(_ session: NetworkSession) {
        updateOfflineMark()
        chatLogs.connectionChanged(session)
    }

    // MARK: Selection

    public var selectedSession: NetworkSession? {
        guard let id = selectedBufferID else { return nil }
        return session(for: id.networkID)
    }

    public var selectedBuffer: BufferModel? {
        guard let id = selectedBufferID else { return nil }
        return session(for: id.networkID)?.buffer(id: id)
    }

    public func session(for id: UUID) -> NetworkSession? {
        sessions.first { $0.id == id }
    }

    public func select(_ buffer: BufferModel) {
        guard selectedBufferID != buffer.id else { return }
        // The buffer being left was on screen: it's read to its newest line.
        if isWindowActive, let previous = selectedBuffer { selectedSession?.markRead(previous) }
        selectedBufferID = buffer.id
        lastSelectedOnNetwork[buffer.id.networkID] = buffer.id
        prepareUnreadMarker(buffer)
        session(for: buffer.id.networkID)?.markRead(buffer)
        // Demo mode shares the real app's defaults; don't replace the
        // channel Vela reopens with a demo one (or, in Vela Dev, one of the
        // developer simulator's).
        #if DEBUG
        let remembers = !isDemo && !DevSimulator.isSimulated(buffer.id.networkID)
        #else
        let remembers = !isDemo
        #endif
        if remembers { UserDefaults.standard.set(buffer.id.description, forKey: "Vela.lastSelectedBuffer") }
    }

    public func select(bufferID: BufferID) {
        guard let buffer = session(for: bufferID.networkID)?.buffer(id: bufferID) else { return }
        select(buffer)
    }

    /// Every selectable buffer, in sidebar order.
    public var orderedBuffers: [BufferModel] {
        sessions.flatMap { $0.isBouncerControl ? [$0.serverBuffer] : $0.allBuffers }
    }

    /// The buffer you were last on in `session` (its console if none, or
    /// if that one's gone).
    public func lastSelectedBuffer(in session: NetworkSession) -> BufferModel {
        if let id = lastSelectedOnNetwork[session.id], let buffer = session.buffer(id: id) { return buffer }
        return session.serverBuffer
    }

    /// ⇧⌘[ / ⇧⌘] and ⌃⇧Tab / ⌃Tab: the previous or next tab of the selected
    /// network (its console, channels, then conversations), wrapping
    /// around at the ends, like a browser's tabs.
    public func selectAdjacentTab(forward: Bool) {
        guard let session = selectedSession ?? sessions.first else { return }
        let tabs = session.allBuffers
        guard tabs.count > 1 else { return }
        guard let index = tabs.firstIndex(where: { $0.id == selectedBufferID }) else {
            select(tabs[forward ? 0 : tabs.count - 1])
            return
        }
        select(tabs[(index + (forward ? 1 : -1) + tabs.count) % tabs.count])
    }

    /// ⌃⌘[ / ⌃⌘]: the previous or next network, in the order of the
    /// sidebar and the network tabs, wrapping around, on the buffer you
    /// were last on there.
    public func selectAdjacentNetwork(forward: Bool) {
        guard !sessions.isEmpty else { return }
        guard let current = selectedSession, let index = sessions.firstIndex(where: { $0.id == current.id }) else {
            select(lastSelectedBuffer(in: sessions[forward ? 0 : sessions.count - 1]))
            return
        }
        guard sessions.count > 1 else { return }
        select(lastSelectedBuffer(in: sessions[(index + (forward ? 1 : -1) + sessions.count) % sessions.count]))
    }

    public func selectAdjacentBuffer(forward: Bool, unreadOnly: Bool = false) {
        let all = orderedBuffers
        guard !all.isEmpty else { return }
        let start = all.firstIndex { $0.id == selectedBufferID } ?? (forward ? -1 : all.count)
        var index = start
        for _ in 0..<all.count {
            index = (index + (forward ? 1 : -1) + all.count) % all.count
            let candidate = all[index]
            if !unreadOnly || candidate.unreadCount > 0 || candidate.highlightCount > 0 {
                select(candidate)
                return
            }
        }
    }

    private func prepareUnreadMarker(_ buffer: BufferModel) {
        buffer.unreadMarkerAfter = buffer.unreadCount > 0 ? (buffer.lastReadAt ?? .distantPast) : nil
    }

    private func restoreSelection() {
        if let saved = UserDefaults.standard.string(forKey: "Vela.lastSelectedBuffer"),
           let buffer = orderedBuffers.first(where: { $0.id.description == saved })
        {
            select(buffer)
        } else if let first = orderedBuffers.first {
            select(first)
        }
    }

    // MARK: Networks

    public func addNetwork(_ config: NetworkConfig, secrets: NetworkSecrets) {
        var config = config
        config.sortOrder = (networkStore.networks.map(\.sortOrder).max() ?? 0) + 1
        storeSecrets(secrets, for: &config)
        networkStore.upsert(config)
        let session = makeSession(for: config)
        sessions.append(session)
        sortSessions()
        select(session.serverBuffer)
        if config.autoConnect { session.connect() }
    }

    public func updateNetwork(_ config: NetworkConfig, secrets: NetworkSecrets?) {
        var config = keepingPosition(config)
        // Parts and detaches waiting for the bouncer are the session's: the
        // network editor's copy may be older.
        if let live = session(for: config.id)?.config {
            config.pendingParts = live.pendingParts
            config.pendingDetaches = live.pendingDetaches
        }
        if let secrets { storeSecrets(secrets, for: &config) }
        networkStore.upsert(config)
        session(for: config.id)?.updateConfig(config)
        sortSessions()
        // Turning auto-connect on or off changes whether it should be online.
        updateOfflineMark()
    }

    public func removeNetwork(id: UUID) {
        for child in networkStore.networks where child.parentNetworkID == id {
            removeNetwork(id: child.id)
        }
        if let session = session(for: id) {
            session.shutdown()
            sessions.removeAll { $0.id == id }
        }
        if selectedBufferID?.networkID == id { selectedBufferID = nil }
        forgetClosed(inNetwork: id)
        savedMessagesObserver?.networkRemoved(id)
        for purpose in [Keychain.SecretPurpose.serverPassword, .saslPassword, .nickServPassword] {
            keychain.deleteSecret(account: Keychain.account(networkID: id, purpose: purpose))
        }
        networkStore.remove(id: id)
        if let database { Task { try? await database.deleteNetwork(id) } }
        if selectedBufferID == nil, let first = orderedBuffers.first { select(first) }
        updateDock()
    }

    public func secrets(for networkID: UUID) -> NetworkSecrets {
        NetworkSecrets(
            serverPassword: keychain.secret(account: Keychain.account(networkID: networkID, purpose: .serverPassword)),
            saslPassword: keychain.secret(account: Keychain.account(networkID: networkID, purpose: .saslPassword)),
            nickServPassword: keychain.secret(account: Keychain.account(networkID: networkID, purpose: .nickServPassword))
        )
    }

    private func storeSecrets(_ secrets: NetworkSecrets, for config: inout NetworkConfig) {
        func store(_ value: String?, _ purpose: Keychain.SecretPurpose) {
            let account = Keychain.account(networkID: config.id, purpose: purpose)
            if let value, !value.isEmpty {
                try? keychain.setSecret(value, account: account)
            } else {
                keychain.deleteSecret(account: account)
            }
        }
        store(secrets.serverPassword, .serverPassword)
        store(secrets.saslPassword, .saslPassword)
        store(secrets.nickServPassword, .nickServPassword)
        config.hasServerPassword = !(secrets.serverPassword ?? "").isEmpty
    }

    private func makeSession(for config: NetworkConfig) -> NetworkSession {
        let session = NetworkSession(config: config, database: database)
        wire(session)
        return session
    }

    /// Connects `session` to the app: its host, the keychain its channel
    /// keys are in, and what `/join`, `/query`, `/part` and `/close` do in
    /// the window.
    private func wire(_ session: NetworkSession) {
        session.host = self
        session.keychain = keychain
        session.requestSelection = { [weak self] buffer in self?.select(buffer) }
        session.requestClose = { [weak self] buffer in self?.close(buffer) }
        session.requestLeave = { [weak self] channel, reason in self?.leave(channel, reason: reason) }
    }

    private func sortSessions() {
        let order = Dictionary(uniqueKeysWithValues: networkStore.networks.enumerated().map { ($1.id, $0) })
        sessions.sort { lhs, rhs in
            // Keep bouncer children right after their parent.
            let l = lhs.config.parentNetworkID.flatMap { order[$0] } ?? order[lhs.id] ?? 0
            let r = rhs.config.parentNetworkID.flatMap { order[$0] } ?? order[rhs.id] ?? 0
            if l != r { return l < r }
            if (lhs.config.parentNetworkID == nil) != (rhs.config.parentNetworkID == nil) { return lhs.config.parentNetworkID == nil }
            let lo = order[lhs.id] ?? .max
            let ro = order[rhs.id] ?? .max
            if lo != ro { return lo < ro }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    // MARK: Network order

    /// The networks `id` can be moved among, in display order: the
    /// top-level networks (standalone and bouncers), or the networks of the
    /// same bouncer.
    public func networkSiblings(of id: UUID) -> [NetworkSession] {
        guard let session = session(for: id) else { return [] }
        let parent = session.config.parentNetworkID
        return sessions.filter { $0.config.parentNetworkID == parent }
    }

    /// Moves network `id` to `index` among its siblings (see
    /// `networkSiblings(of:)`). A bouncer takes its networks with it.
    public func moveNetwork(_ id: UUID, toIndex index: Int) {
        guard let moving = session(for: id) else { return }
        var siblings = networkSiblings(of: id).map(\.id)
        guard let from = siblings.firstIndex(of: id) else { return }
        let to = min(max(0, index), siblings.count - 1)
        guard from != to else { return }
        siblings.remove(at: from)
        siblings.insert(id, at: to)

        // Rebuild the whole order: each top-level network, then its children.
        var topLevel = sessions.filter { $0.config.parentNetworkID == nil }.map(\.id)
        var children: [UUID: [UUID]] = [:]
        for session in sessions {
            if let parent = session.config.parentNetworkID { children[parent, default: []].append(session.id) }
        }
        if let parent = moving.config.parentNetworkID { children[parent] = siblings } else { topLevel = siblings }
        var order: [UUID] = []
        for parent in topLevel {
            order.append(parent)
            order += children[parent] ?? []
        }
        order += sessions.map(\.id).filter { !order.contains($0) }
        applyNetworkOrder(order)
    }

    /// Moves network `id` `offset` places among its siblings (negative is up/left).
    public func moveNetwork(_ id: UUID, by offset: Int) {
        guard let index = networkSiblings(of: id).firstIndex(where: { $0.id == id }) else { return }
        moveNetwork(id, toIndex: index + offset)
    }

    private func applyNetworkOrder(_ order: [UUID]) {
        let position = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        sessions.sort { (position[$0.id] ?? .max) < (position[$1.id] ?? .max) }
        networkStore.reorder(order)
        // Sessions save their own config (auto-join changes, nick); keep
        // their copies in step so they don't write an old position back.
        for session in sessions {
            if let stored = networkStore.network(id: session.id) { session.config.sortOrder = stored.sortOrder }
        }
    }

    /// A bouncer network whose bouncer was removed. It isn't connected at
    /// launch, and doesn't count as offline.
    func isOrphanedChild(_ session: NetworkSession) -> Bool {
        guard let parent = session.config.parentNetworkID else { return false }
        return networkStore.networks.first { $0.id == parent } == nil
    }

    // MARK: Media policy

    /// What links in `bufferID` may preview, and how previews look there.
    public func previewContext(for bufferID: BufferID?) -> PreviewContext {
        var policy = MediaPolicy()
        policy.autoLoad = settings[.mediaAutoLoad]
        policy.showLinkCards = settings[.mediaShowLinkCards]
        policy.siteRules = siteRules
        policy.filterAdultSites = settings[.mediaFilterAdultSites]
        // A placeholder adult site for demo screenshots (never resolves).
        if isDemo { policy.extraAdultDomains = ["nsfw.example"] }
        policy.restrictToAllowedDomains = settings[.mediaRestrictToAllowed]
        policy.maxImageBytes = Int(settings[.mediaMaxImageSizeMB] * 1024 * 1024)
        policy.browserFallback = settings[.mediaBrowserFallback]
        if let bufferID, !isMediaEnabled(for: bufferID) { policy.autoLoad = false }
        let blurImages = settings[.mediaBlurImages] || (bufferID.map(isBlurred(for:)) ?? false)
        return PreviewContext(policy: policy, layout: previewLayout, blurImages: blurImages)
    }

    /// Preview sizes from `media.linkPreviewSize`, `media.videos` and
    /// `media.imageSize` (VelaMedia mirrors them; the raw values match).
    private var previewLayout: VelaMedia.PreviewLayout {
        VelaMedia.PreviewLayout(
            linkSize: PreviewLinkSize(rawValue: settings[.mediaLinkPreviewSize].rawValue) ?? .standard,
            videoStyle: PreviewVideoStyle(rawValue: settings[.mediaVideos].rawValue) ?? .player,
            imageSize: PreviewImageSize(rawValue: settings[.mediaImageSize].rawValue) ?? .full
        )
    }

    /// Per-site preview rules (`media.siteRules`), plus any older blocked and
    /// allowed domain lists that the next launch will migrate into it
    /// (merged the way `SettingsMigration` merges them). Parsed once per
    /// settings value: `previewContext(for:)` runs in every embed view's body.
    public var siteRules: SiteRules {
        let source = SettingsMigration.migrated(settings.values, rules: [.mergeDomainListsIntoSiteRules])[
            SettingKey<[String: JSONValue]>.mediaSiteRules.key
        ]?.objectValue ?? [:]
        if let cache = siteRulesCache, cache.source == source { return cache.rules }
        let rules = SiteRules(source.compactMapValues(\.stringValue))
        siteRulesCache = (source, rules)
        return rules
    }

    /// The rule that decides previews from `url`'s site, if any.
    public func siteRule(for url: URL) -> (domain: String, access: SiteAccess)? {
        siteRules.access(for: url)
    }

    /// Sets (or, with nil, removes) the rule for `domain` and its subdomains.
    public func setSiteRule(_ access: SiteAccess?, forDomain domain: String) {
        guard let normalized = SiteRules.normalizedDomain(domain) else { return }
        // Fold older blocked/allowed lists (written since launch) into
        // media.siteRules first; they would otherwise put the rule back.
        for change in SettingsMigration.changes(for: settings.values, rules: [.mergeDomainListsIntoSiteRules]) {
            settings.setValue(change.value, forKey: change.key)
        }
        var raw = settings[.mediaSiteRules]
        for key in raw.keys where SiteRules.normalizedDomain(key) == normalized { raw[key] = nil }
        if let access { raw[normalized] = .string(access.rawValue) }
        settings[.mediaSiteRules] = raw
    }

    /// "Always allow" on a blocked preview: an allow rule for its site.
    public func alwaysAllow(_ block: SiteBlock) {
        setSiteRule(.allow, forDomain: block.domain)
    }

    /// "Unblock" on a preview you blocked yourself: removes your rule.
    public func unblock(_ block: SiteBlock) {
        setSiteRule(nil, forDomain: block.domain)
    }

    // MARK: Media per buffer

    /// Whether inline media is on in `bufferID`: neither it nor its network
    /// is in `media.disabledBuffers`.
    public func isMediaEnabled(for bufferID: BufferID) -> Bool {
        !BufferScopeList(settings[.mediaDisabledBuffers]).contains(bufferID)
    }

    /// Inline media for every buffer of a network (`"<network>/*"` in `media.disabledBuffers`).
    public func isMediaEnabled(forNetwork networkID: UUID) -> Bool {
        !BufferScopeList(settings[.mediaDisabledBuffers]).containsNetwork(networkID)
    }

    public func setMediaEnabled(_ enabled: Bool, forNetwork networkID: UUID) {
        updateBufferScopeList(.mediaDisabledBuffers) { $0.set(!enabled, forNetwork: networkID) }
    }

    /// Turns media on or off for one buffer. A buffer stays off while its
    /// whole network is off.
    public func setMediaEnabled(_ enabled: Bool, for bufferID: BufferID) {
        updateBufferScopeList(.mediaDisabledBuffers) { $0.set(!enabled, for: bufferID) }
    }

    // MARK: Blur per buffer

    /// Whether `bufferID` (or its network) is in `media.blurredBuffers`, so
    /// its images stay blurred until clicked. `media.blurImages` blurs every
    /// buffer on top of this; ``previewContext(for:)`` combines the two.
    public func isBlurred(for bufferID: BufferID) -> Bool {
        BufferScopeList(settings[.mediaBlurredBuffers]).contains(bufferID)
    }

    /// Images blurred in every buffer of a network (`"<network>/*"` in `media.blurredBuffers`).
    public func isBlurred(forNetwork networkID: UUID) -> Bool {
        BufferScopeList(settings[.mediaBlurredBuffers]).containsNetwork(networkID)
    }

    /// Blurs images in one buffer, or stops. A buffer stays blurred while
    /// its whole network is.
    public func setBlurred(_ blurred: Bool, for bufferID: BufferID) {
        updateBufferScopeList(.mediaBlurredBuffers) { $0.set(blurred, for: bufferID) }
    }

    public func setBlurred(_ blurred: Bool, forNetwork networkID: UUID) {
        updateBufferScopeList(.mediaBlurredBuffers) { $0.set(blurred, forNetwork: networkID) }
    }

    // MARK: Translation per buffer

    /// Whether messages in `bufferID` (or its network) are translated
    /// automatically (`translation.autoTranslate`).
    public func isAutoTranslated(_ bufferID: BufferID) -> Bool {
        BufferScopeList(settings[.translationAutoTranslate]).contains(bufferID)
    }

    public func isAutoTranslated(network networkID: UUID) -> Bool {
        BufferScopeList(settings[.translationAutoTranslate]).containsNetwork(networkID)
    }

    /// A buffer stays translated while its whole network is.
    public func setAutoTranslated(_ enabled: Bool, for bufferID: BufferID) {
        updateBufferScopeList(.translationAutoTranslate) { $0.set(enabled, for: bufferID) }
    }

    public func setAutoTranslated(_ enabled: Bool, network networkID: UUID) {
        updateBufferScopeList(.translationAutoTranslate) { $0.set(enabled, forNetwork: networkID) }
    }

    private func updateBufferScopeList(_ key: SettingKey<[String]>, _ update: (inout BufferScopeList) -> Void) {
        var list = BufferScopeList(settings[key])
        update(&list)
        settings[key] = list.entries
    }

    // MARK: System integration

    public var totalHighlights: Int { sessions.reduce(0) { $0 + $1.totalHighlights } }

    private func observeSystem() {
        let center = NSWorkspace.shared.notificationCenter
        systemObservers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.systemWillSleep() }
        })
        systemObservers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.systemDidWake() }
        })

        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in
                self?.sessions.forEach { $0.networkPathBecameAvailable() }
            }
        }
        monitor.start(queue: DispatchQueue(label: "vela.path-monitor"))
        pathMonitor = monitor

        (notifier as? UserNotificationNotifier)?.onActivate = { [weak self] bufferID in
            self?.select(bufferID: bufferID)
            NSApp.activate()
        }

        // Switching to Vela stops a Dock bounce.
        systemObservers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancelDockAttention() }
        })
    }

    private func systemWillSleep() {
        sessionsConnectedBeforeSleep = Set(sessions.filter { $0.connectionState != .disconnected }.map(\.id))
        for session in sessions where sessionsConnectedBeforeSleep.contains(session.id) {
            session.disconnect(reason: "Computer going to sleep")
        }
    }

    private func systemDidWake() {
        let toReconnect = sessionsConnectedBeforeSleep
        sessionsConnectedBeforeSleep = []
        Task {
            try? await Task.sleep(for: .seconds(2))
            for session in sessions where toReconnect.contains(session.id) { session.connect() }
        }
    }

    /// Flush pending writes and quit politely.
    public func prepareForTermination() {
        // Quitting disconnects every network; that's no reason for the Dock
        // to show anything.
        stopDockUpdates()
        settings.flush()
        for session in sessions { session.shutdown() }
        // Write what's queued and end each log with "Log closed".
        chatLogs.shutdown()
        // Demo data is throwaway: remove this run's scratch folders.
        if isDemo { DemoScratch.removeOwn() }
    }

    /// Drops cached link previews fetched more than `previewCacheMaxAge` ago.
    private func prunePreviewCache() {
        guard let database else { return }
        let cutoff = Date().addingTimeInterval(-Self.previewCacheMaxAge)
        Task { try? await database.prunePreviews(olderThan: cutoff) }
    }

    /// How long cached link previews are kept: 30 days.
    static let previewCacheMaxAge: TimeInterval = 30 * 86_400

    private func pruneHistoryIfNeeded() {
        let days = settings[.historyRetentionDays]
        guard days > 0, let database else { return }
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        Task { try? await database.pruneMessages(olderThan: cutoff) }
    }

    public static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1"
    }

    // MARK: Demo support

    func installDemoSessions(_ demoSessions: [NetworkSession], selectsChannel: Bool = true) {
        for session in demoSessions { wire(session) }
        sessions = demoSessions
        guard selectsChannel else { return }
        if let buffer = demoSessions.first?.buffer(named: "#vela") ?? demoSessions.first?.channels.first { select(buffer) }
    }

    #if DEBUG
    // MARK: Developer simulator (Vela Dev only)

    /// Adds a network made by `DevSimulator`. It's in memory only: not in
    /// networks.json, and `host` keeps it out of chat logs, the Dock's
    /// offline mark and saved settings.
    func installSimulatedSession(_ session: NetworkSession, host: SessionHost) {
        wire(session)
        session.host = host
        sessions.append(session)
    }

    /// Takes a simulated network away, selecting another buffer if one of
    /// its buffers was selected.
    func removeSimulatedSession(_ session: NetworkSession) {
        session.shutdown()
        let wasSelected = selectedBufferID?.networkID == session.id
        sessions.removeAll { $0 === session }
        lastSelectedOnNetwork[session.id] = nil
        guard wasSelected else { return }
        selectedBufferID = nil
        if let buffer = orderedBuffers.first { select(buffer) }
    }
    #endif
}

/// Stores LinkPreview values in the SQLite cache, while `history.save` is
/// on (``PreviewDiskCacheSwitch``). Off, previews stay in the preview
/// service's memory and are fetched again after a relaunch.
nonisolated struct DatabasePreviewCache: LinkPreviewCache {
    let database: VelaDatabase
    let diskCache: PreviewDiskCacheSwitch

    func cachedPreview(for url: URL) async -> LinkPreview? {
        guard diskCache.isOn, let data = try? await database.cachedPreviewJSON(url: url.absoluteString) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let preview = try? decoder.decode(LinkPreview.self, from: data) else { return nil }
        // Re-fetch page previews after a week.
        if preview.kind == .page, preview.fetchedAt < Date().addingTimeInterval(-7 * 86_400) { return nil }
        return preview
    }

    func storePreview(_ preview: LinkPreview) async {
        guard diskCache.isOn else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(preview) else { return }
        try? await database.storePreviewJSON(data, url: preview.url.absoluteString)
    }
}

/// A request to bring a buffer on screen; see ``AppModel/requestShow(_:draft:appendingDraft:line:)``.
/// Each request is distinct, so asking twice for the same buffer still fires.
nonisolated public struct ShowRequest: Equatable, Sendable {
    public let id = UUID()
    public let bufferID: BufferID
    /// Text to put in the buffer's composer.
    public var draft: String?
    /// Put ``draft`` after the composer's text rather than in its place.
    public var appendsDraft = false
    /// A message to scroll to.
    public var line: LineReference?
}

nonisolated extension ShowRequest {
    /// What the message box holds once `draft` is put in it, given what it
    /// holds now (`existing`). Replacing, it's `draft` as is. Appending
    /// (a `vela://draft` link, AppleScript's `draft`), what you were typing
    /// stays, with the draft after it, and a draft that would start the box
    /// with "/" gets the composer's "//" escape, so pressing Return sends it
    /// as text rather than running it as a command. Nil when appending to a
    /// command you're typing, which is left alone.
    public static func composerText(existing: String?, draft: String, appending: Bool) -> String? {
        guard appending else { return draft }
        let current = existing ?? ""
        if current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return draft.hasPrefix("/") ? "/" + draft : draft
        }
        if current.drop(while: \.isWhitespace).hasPrefix("/") { return nil }
        if current.last?.isWhitespace == true { return current + draft }
        return current + (draft.contains(where: \.isNewline) ? "\n" : " ") + draft
    }
}

/// One message in a buffer: its line id, and its time, which tells how far
/// back to load history to find it.
nonisolated public struct LineReference: Equatable, Hashable, Sendable {
    public var id: UUID
    public var time: Date

    public init(id: UUID, time: Date) {
        self.id = id
        self.time = time
    }
}
