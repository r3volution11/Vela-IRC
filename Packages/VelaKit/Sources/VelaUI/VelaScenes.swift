// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppIntents
import AppKit
import SwiftUI
import VelaCore
import VelaIntelligence
import VelaIntents
import VelaStore
import VelaTheme

/// All of Vela's scenes. The app target only instantiates this.
public struct VelaScenes: Scene {
    @State private var app: AppModel
    @State private var themeStore: ThemeStore
    @State private var uiState: UIState
    @State private var services: SceneServices
    @State private var siri: SiriSceneSupport

    /// Makes the app's models and services and registers them with App
    /// Intents (`AppDependencyManager`). Call it from the app's `init()`,
    /// as Apple's App Intents pattern does: Siri and Shortcuts can launch
    /// Vela to run an action, and its dependencies must be registered
    /// before the action runs, not whenever SwiftUI first builds the
    /// scenes. ``init(appShortcuts:)`` reuses what this made.
    ///
    /// - Parameter appShortcuts: As for ``init(appShortcuts:)``.
    public static func prepare(appShortcuts: (any AppShortcutsProvider.Type)? = nil) {
        _ = AppInstances.shared(appShortcuts: appShortcuts)
    }

    /// - Parameter appShortcuts: The app's App Shortcuts, refreshed when
    ///   channels change so phrases like "Open #vela in Vela" stay current.
    public init(appShortcuts: (any AppShortcutsProvider.Type)? = nil) {
        // SwiftUI can run this more than once; every run gets the same
        // instances (see `AppInstances`).
        let shared = AppInstances.shared(appShortcuts: appShortcuts)
        _app = State(initialValue: shared.app)
        _themeStore = State(initialValue: shared.themeStore)
        _uiState = State(initialValue: shared.uiState)
        _services = State(initialValue: shared.services)
        _siri = State(initialValue: shared.siri)
    }

    public var body: some Scene {
        Window("Vela", id: WindowID.main) {
            MainWindowView()
                .velaEnvironment(app: app, themeStore: themeStore, uiState: uiState, services: services, isPrimary: true)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1180, height: 760)
        // The scroll benchmark opens a window of its own.
        .defaultLaunchBehavior(ScrollBenchmark.isActive ? .suppressed : .presented)
        // Always open the main window at launch. Restoring saved window
        // state could otherwise restore "no windows" after a crash or a
        // force quit, leaving Vela running with nothing on screen.
        .restorationBehavior(.disabled)
        .commands {
            VelaCommands(app: app, themeStore: themeStore, uiState: uiState)
            ShowRequestCommands(router: siri.showRequests)
        }

        Settings {
            SettingsRootView()
                .velaEnvironment(app: app, themeStore: themeStore, uiState: uiState, services: services, isPrimary: false)
        }
        .defaultSize(width: 820, height: 600)
        .windowResizability(.contentMinSize)

        Window("Theme Editor", id: WindowID.themeEditor) {
            ThemeEditorView()
                .velaEnvironment(app: app, themeStore: themeStore, uiState: uiState, services: services, isPrimary: false)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 760, height: 680)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
    }
}

public enum WindowID {
    public static let main = "main"
    public static let themeEditor = "theme-editor"
}

extension View {
    /// Injects the shared models, the resolved theme and the chat style.
    func velaEnvironment(app: AppModel, themeStore: ThemeStore, uiState: UIState, services: SceneServices, isPrimary: Bool) -> some View {
        modifier(VelaEnvironmentModifier(app: app, themeStore: themeStore, uiState: uiState, services: services, isPrimary: isPrimary))
    }
}

/// The app's models and services: one set per process, made by the first
/// `VelaScenes.init`. SwiftUI may initialize the scene more than once (it
/// keeps the first `@State` values); later inits reuse these instead of
/// making a second `AppModel` that Siri, Shortcuts and Spotlight would be
/// handed through their dependencies while the window shows the first.
@MainActor
private final class AppInstances {
    let app: AppModel
    let themeStore: ThemeStore
    let uiState: UIState
    let services: SceneServices
    let siri: SiriSceneSupport
    /// Shows the chosen Dock icon (`appearance.appIcon`), the DEV band and
    /// the offline mark. Snapshot runs leave the Dock alone.
    let dockIcon: DockIconController?

    private static var current: AppInstances?

    static func shared(appShortcuts: (any AppShortcutsProvider.Type)?) -> AppInstances {
        if let current { return current }
        let instances = AppInstances(appShortcuts: appShortcuts)
        current = instances
        return instances
    }

    private init(appShortcuts: (any AppShortcutsProvider.Type)?) {
        // Vela opens no documents. Without this, AppKit treats launch
        // arguments such as the "Lighter" in `--theme Lighter` as files to
        // open, and a launch that opens files skips the main window.
        UserDefaults.standard.register(defaults: ["NSTreatUnknownArgumentsAsOpen": "NO"])
        // One main window, never in window tabs. This also keeps AppKit's
        // View → Show Tab Bar items out of the menus, so they can't clash
        // with Reopen Closed Channel (⇧⌘T).
        NSWindow.allowsAutomaticWindowTabbing = false
        let arguments = ProcessInfo.processInfo.arguments
        let demo = UserDefaults.standard.bool(forKey: "VelaDemoMode") || arguments.contains("--demo")
        // The scroll benchmark's media comes from local stand-ins, set up
        // before anything can fetch.
        if ScrollBenchmark.isActive { ScrollBenchmark.prepareMedia() }
        let app = demo ? AppModel.demo() : AppModel.live()
        if demo {
            DemoArguments.apply(arguments, to: app.settings)
            DemoArguments.selectBuffer(from: arguments, in: app)
        }
        if ScrollBenchmark.isActive { ScrollBenchmark.prepare(app) }
        // Demo runs (screenshots, UI work) get their own temporary Themes
        // folder, so they never show or change the real one.
        let themeStore = ThemeStore(userThemesDirectory: demo ? DemoArguments.themesDirectory(for: arguments) : AppPaths.themesDirectory)
        let uiState = UIState()
        let services = SceneServices(intelligence: demo ? .demo() : .live())
        // Siri, Shortcuts and Spotlight run App Intents in this process;
        // they reach the same model and services through dependencies,
        // registered here once, from the app's init (`VelaScenes.prepare`).
        AppDependencyManager.shared.add(dependency: app)
        AppDependencyManager.shared.add(dependency: services.intelligence)
        if SnapshotSupport.isActive {
            SnapshotSupport.scheduleOffscreenCapture(app: app, themeStore: themeStore, uiState: uiState, services: services)
        } else if ScrollBenchmark.isActive {
            ScrollBenchmark.schedule(app: app, themeStore: themeStore, uiState: uiState, services: services)
        }
        self.app = app
        self.themeStore = themeStore
        self.uiState = uiState
        self.services = services
        self.siri = SiriSceneSupport(app: app, uiState: uiState, appShortcuts: appShortcuts)
        if SnapshotSupport.isActive {
            dockIcon = nil
        } else {
            let dockIcon = DockIconController(settings: app.settings, isOffline: { [weak app] in app?.showsOfflineMark ?? false })
            dockIcon.start()
            self.dockIcon = dockIcon
        }
    }
}

/// App-wide services shared by every scene, beyond the core models.
@MainActor
final class SceneServices {
    let intelligence: IntelligenceServices
    let translations = TranslationStore()

    init(intelligence: IntelligenceServices) {
        self.intelligence = intelligence
    }
}

private struct VelaEnvironmentModifier: ViewModifier {
    let app: AppModel
    let themeStore: ThemeStore
    let uiState: UIState
    let services: SceneServices
    let isPrimary: Bool

    /// Bumped when macOS's locale changes (such as the 24-hour time switch
    /// in System Settings), so the chat style re-resolves a System clock.
    @State private var localeRevision = 0
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        let theme = themeStore.current
        let _ = localeRevision  // Re-run body (and rebuild ChatStyle) when it changes.
        content
            .environment(app)
            .environment(themeStore)
            .environment(uiState)
            .environment(services.intelligence)
            .environment(services.translations)
            .environment(\.theme, theme)
            .environment(\.chatStyle, ChatStyle(settings: app.settings))
            .onReceive(
                NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)
                    .receive(on: DispatchQueue.main)
            ) { _ in
                localeRevision &+= 1
            }
            .tint(theme[ThemeKey.accent])
            .preferredColorScheme(theme.kind == .dark ? .dark : .light)
            .onChange(of: ThemeSettings(settings: app.settings), initial: true) { _, newValue in
                themeStore.settings = newValue
            }
            .task {
                guard isPrimary else { return }
                themeStore.start()
                app.start()
                ShowRequestRouter.shared?.installIfNeeded(openWindow)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                guard isPrimary else { return }
                app.prepareForTermination()
            }
    }
}

// MARK: - Siri, Shortcuts and Spotlight

/// Siri, Shortcuts and Spotlight support for the app's lifetime.
@MainActor
final class SiriSceneSupport {
    let showRequests: ShowRequestRouter
    let integration: SiriIntegration

    /// Refreshes the parameters (channel names) of `provider`'s phrases.
    private static func refresher<Provider: AppShortcutsProvider>(for provider: Provider.Type) -> @MainActor () -> Void {
        { Provider.updateAppShortcutParameters() }
    }

    /// Made once per process (by `AppInstances`), so it starts right away.
    init(app: AppModel, uiState: UIState, appShortcuts: (any AppShortcutsProvider.Type)?) {
        showRequests = ShowRequestRouter(app: app, uiState: uiState)
        integration = SiriIntegration(app: app, refreshAppShortcuts: appShortcuts.map { Self.refresher(for: $0) })
        ShowRequestRouter.shared = showRequests
        showRequests.start()
        integration.start()
    }
}

/// Brings a buffer on screen when Siri, Shortcuts or Spotlight ask
/// (`AppModel.showRequest`): selects it, puts any draft in its composer,
/// activates Vela and opens the main window if it was closed. Lives as long
/// as the app, so it works with no window open.
@MainActor
final class ShowRequestRouter {
    private let app: AppModel
    private let uiState: UIState
    private var openWindow: OpenWindowAction?
    private var handled: UUID?

    /// The router of the running app.
    static weak var shared: ShowRequestRouter?

    init(app: AppModel, uiState: UIState) {
        self.app = app
        self.uiState = uiState
    }

    func start() {
        observe()
    }

    /// Captured from an environment that outlives the main window (the
    /// menu bar's commands).
    func install(_ action: OpenWindowAction) {
        openWindow = action
    }

    /// A fallback from the main window, if the menu bar's hasn't arrived.
    func installIfNeeded(_ action: OpenWindowAction) {
        if openWindow == nil { openWindow = action }
    }

    private func observe() {
        withObservationTracking {
            _ = app.showRequest
        } onChange: { [weak self] in
            // Runs before the change lands; act on it right after.
            Task { @MainActor in
                self?.handle()
                self?.observe()
            }
        }
    }

    private func handle() {
        guard let request = app.showRequest, request.id != handled else { return }
        handled = request.id
        if let draft = request.draft { uiState.drafts[request.bufferID] = draft }
        // Select first: the window shows the selection when it opens.
        app.select(bufferID: request.bufferID)
        NSApp.activate()
        // Opens the main window, or brings it forward if it's open.
        openWindow?(id: WindowID.main)
        uiState.focusInput()
    }
}

/// Hands the menu bar's `openWindow` to the show-request router. The menu
/// bar exists even when every window is closed.
private struct ShowRequestCommands: Commands {
    let router: ShowRequestRouter

    var body: some Commands {
        CommandGroup(after: .windowArrangement) {
            OpenWindowBridge(router: router)
        }
    }
}

private struct OpenWindowBridge: View {
    @Environment(\.openWindow) private var openWindow
    let router: ShowRequestRouter

    var body: some View {
        let _ = router.install(openWindow)
        EmptyView()
    }
}
