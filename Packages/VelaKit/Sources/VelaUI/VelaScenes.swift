// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import VelaCore
import VelaStore
import VelaTheme

/// All of Vela's scenes. The app target only instantiates this.
public struct VelaScenes: Scene {
    @State private var app: AppModel
    @State private var themeStore: ThemeStore
    @State private var uiState: UIState

    public init() {
        let arguments = ProcessInfo.processInfo.arguments
        let demo = UserDefaults.standard.bool(forKey: "VelaDemoMode") || arguments.contains("--demo")
        let app = demo ? AppModel.demo() : AppModel.live()
        if demo { DemoArguments.apply(arguments, to: app.settings) }
        let themeStore = ThemeStore(userThemesDirectory: AppPaths.themesDirectory)
        let uiState = UIState()
        if SnapshotSupport.isActive {
            SnapshotSupport.scheduleOffscreenCapture(app: app, themeStore: themeStore, uiState: uiState)
        }
        _app = State(initialValue: app)
        _themeStore = State(initialValue: themeStore)
        _uiState = State(initialValue: uiState)
    }

    public var body: some Scene {
        Window("Vela", id: WindowID.main) {
            MainWindowView()
                .velaEnvironment(app: app, themeStore: themeStore, uiState: uiState, isPrimary: true)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1180, height: 760)
        .defaultLaunchBehavior(.presented)
        .commands {
            VelaCommands(app: app, themeStore: themeStore, uiState: uiState)
        }

        Settings {
            SettingsRootView()
                .velaEnvironment(app: app, themeStore: themeStore, uiState: uiState, isPrimary: false)
        }

        Window("Theme Editor", id: WindowID.themeEditor) {
            ThemeEditorView()
                .velaEnvironment(app: app, themeStore: themeStore, uiState: uiState, isPrimary: false)
        }
        .windowStyle(.hiddenTitleBar)
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
    func velaEnvironment(app: AppModel, themeStore: ThemeStore, uiState: UIState, isPrimary: Bool) -> some View {
        modifier(VelaEnvironmentModifier(app: app, themeStore: themeStore, uiState: uiState, isPrimary: isPrimary))
    }
}

private struct VelaEnvironmentModifier: ViewModifier {
    let app: AppModel
    let themeStore: ThemeStore
    let uiState: UIState
    let isPrimary: Bool

    func body(content: Content) -> some View {
        let theme = themeStore.current
        content
            .environment(app)
            .environment(themeStore)
            .environment(uiState)
            .environment(\.theme, theme)
            .environment(\.chatStyle, ChatStyle(settings: app.settings))
            .tint(theme[ThemeKey.accent])
            .preferredColorScheme(theme.kind == .dark ? .dark : .light)
            .onChange(of: ThemeSettings(settings: app.settings), initial: true) { _, newValue in
                themeStore.settings = newValue
            }
            .task {
                guard isPrimary else { return }
                themeStore.start()
                app.start()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                guard isPrimary else { return }
                app.prepareForTermination()
            }
    }
}
