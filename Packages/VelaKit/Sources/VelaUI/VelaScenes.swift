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

    /// - Parameter appShortcuts: The app's App Shortcuts, refreshed when
    ///   channels change so phrases like "Open #vela in Vela" stay current.
    public init(appShortcuts: (any AppShortcutsProvider.Type)? = nil) {
        // Vela opens no documents. Without this, AppKit treats launch
        // arguments such as the "Lighter" in `--theme Lighter` as files to
        // open, and a launch that opens files skips the main window.
        UserDefaults.standard.register(defaults: ["NSTreatUnknownArgumentsAsOpen": "NO"])
        let arguments = ProcessInfo.processInfo.arguments
        let demo = UserDefaults.standard.bool(forKey: "VelaDemoMode") || arguments.contains("--demo")
        let app = demo ? AppModel.demo() : AppModel.live()
        if demo {
            DemoArguments.apply(arguments, to: app.settings)
            DemoArguments.selectBuffer(from: arguments, in: app)
        }
        let themeStore = ThemeStore(userThemesDirectory: AppPaths.themesDirectory)
        let uiState = UIState()
        let services = SceneServices(intelligence: demo ? .demo() : .live())
        // Siri, Shortcuts and Spotlight run App Intents in this process;
        // they reach the same model and services through dependencies.
        AppDependencyManager.shared.add(dependency: app)
        AppDependencyManager.shared.add(dependency: services.intelligence)
        if SnapshotSupport.isActive {
            SnapshotSupport.scheduleOffscreenCapture(app: app, themeStore: themeStore, uiState: uiState, services: services)
        }
        _app = State(initialValue: app)
        _themeStore = State(initialValue: themeStore)
        _uiState = State(initialValue: uiState)
        _services = State(initialValue: services)
        _siri = State(initialValue: SiriSceneSupport(app: app, uiState: uiState, appShortcuts: appShortcuts))
    }

    public var body: some Scene {
        Window("Vela", id: WindowID.main) {
            MainWindowView()
                .velaEnvironment(app: app, themeStore: themeStore, uiState: uiState, services: services, isPrimary: true)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1180, height: 760)
        .defaultLaunchBehavior(.presented)
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

    /// `VelaScenes.init` can run more than once; only the first instance
    /// (the one SwiftUI keeps) starts.
    private static var started = false

    /// Refreshes the parameters (channel names) of `provider`'s phrases.
    private static func refresher<Provider: AppShortcutsProvider>(for provider: Provider.Type) -> @MainActor () -> Void {
        { Provider.updateAppShortcutParameters() }
    }

    init(app: AppModel, uiState: UIState, appShortcuts: (any AppShortcutsProvider.Type)?) {
        showRequests = ShowRequestRouter(app: app, uiState: uiState)
        integration = SiriIntegration(app: app, refreshAppShortcuts: appShortcuts.map { Self.refresher(for: $0) })
        guard !Self.started else { return }
        Self.started = true
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
