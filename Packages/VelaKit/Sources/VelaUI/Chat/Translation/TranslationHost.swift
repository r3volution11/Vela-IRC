// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import Translation
import VelaCore
import VelaIntelligence
import VelaStore

extension View {
    /// Runs message translations for the buffer on screen (the system's
    /// translation sessions need a view to attach to).
    ///
    /// Tells the rows below where to translate into and whether the buffer
    /// translates on its own (``TranslationContext``), and hosts the hidden
    /// `.translationTask` that lets macOS ask to download a language.
    func translationHost(buffer: BufferModel) -> some View {
        modifier(TranslationHostModifier(buffer: buffer))
    }
}

extension EnvironmentValues {
    /// Set by `translationHost(buffer:)`; nil where messages can't be translated.
    @Entry var translationContext: TranslationContext?
}

private struct TranslationHostModifier: ViewModifier {
    @Environment(AppModel.self) private var app
    @Environment(TranslationStore.self) private var store
    let buffer: BufferModel

    /// The session macOS opens for a pair that needs a download.
    @State private var configuration: TranslationSession.Configuration?
    @State private var openedRequestID: Int?

    func body(content: Content) -> some View {
        let context = TranslationContext(
            target: TranslationStore.target(setting: app.settings[.translationLanguage], isDemo: app.isDemo),
            isAutomatic: buffer.kind != .server && app.isAutoTranslated(buffer.id),
            isDemo: app.isDemo
        )
        let downloads = store.downloads
        content
            .environment(\.translationContext, context)
            .translationTask(configuration, action: Self.runDownloads(downloads))
            .onChange(of: downloads?.request, initial: true) { _, request in
                open(request)
            }
            .onChange(of: context.target, initial: true) { _, target in
                store.retarget(to: target, isDemo: context.isDemo)
            }
            .onAppear { store.prepare(isDemo: context.isDemo) }
            .onDisappear { downloads?.cancelAll() }
    }

    /// Points the translation task at the requested pair. Asking again for
    /// the pair already configured (a declined download, then Translate
    /// again) re-runs the task.
    private func open(_ request: TranslationDownloads.Request?) {
        guard let request, request.id != openedRequestID else { return }
        openedRequestID = request.id
        if var current = configuration, current.source == request.pair.source, current.target == request.pair.target {
            current.invalidate()
            configuration = current
        } else {
            configuration = TranslationSession.Configuration(source: request.pair.source, target: request.pair.target)
        }
    }

    /// The task's action, made outside the view so it isn't tied to the main
    /// actor: the session isn't Sendable and must stay with the task.
    private nonisolated static func runDownloads(_ downloads: TranslationDownloads?) -> (TranslationSession) async -> Void {
        { session in await downloads?.run(in: session) }
    }
}
