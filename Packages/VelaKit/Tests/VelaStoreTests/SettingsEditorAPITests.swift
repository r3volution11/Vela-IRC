// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
import VelaFoundation
import VelaStore  // deliberately not @testable: only the public contract

/// Compiles the API the settings editor's JSON view codes against, through
/// plain imports, the way VelaUI uses it.
@MainActor
@Suite struct SettingsEditorAPITests {
    @Test func jsonViewContract() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let store = SettingsStore(fileURL: directory.file("settings.json"), watchForChanges: false)

        // Load, watch for changes on disk, save with ⌘S.
        var text = store.fileText()
        let baseline: Int = store.fileRevision
        text = "{\n    // mine\n    \"chat.fontSize\": 15\n}\n"
        try store.saveFileText(text)
        #expect(store.fileRevision != baseline)
        #expect(store.lastError == nil)

        // Highlighting and positions.
        let document = JSONCDocument(text)
        let runs: [JSONCHighlight] = document.highlights()
        #expect(runs.contains { $0.role == .comment })
        let keyRange: NSRange? = document.root?.lastProperty(named: "chat.fontSize")?.keyRange
        #expect(keyRange != nil)
        let (line, column) = document.lineAndColumn(at: keyRange?.location ?? 0)
        #expect((line, column) == (3, 5))

        // Diagnostics.
        let diagnostics: [SettingsDiagnostic] = SettingsValidator.diagnostics(
            for: "{\"chat.fontsize\": 15}",
            extraChecks: ["appearance.colorCustomizations": { _ in [] }]
        )
        #expect(diagnostics.first?.severity == .warning)
        #expect(diagnostics.first?.suggestedKey == "chat.fontSize")

        // Completion and hover.
        let context = SettingsCompletion.context(in: document, at: (text as NSString).range(of: "15").location)
        guard case .value(let position) = context else {
            Issue.record("Expected a value context")
            return
        }
        let items: [SettingsCompletionItem] = SettingsCompletion.items(for: context)
            + [SettingsCompletion.valueItem(16, title: "Bigger", at: position)]
        let filtered = SettingsCompletion.filter(items, matching: position.prefix)
        let accepted = JSONCEdit.apply(filtered.last!.edits, to: text)
        #expect(accepted.contains("\"chat.fontSize\": 16"))
        let hover: SettingsHover? = SettingsCompletion.hover(in: document, at: keyRange!.location + 1)
        #expect(hover?.descriptor?.title == "Chat: Font Size")

        // Copying a default into the editor's text (the defaults pane's ✎).
        let edits: [JSONCEdit] = try JSONCEditing.edits(setting: .string("columns"), at: ["chat.layout"], in: accepted)
        #expect(JSONCEdit.apply(edits, to: accepted).contains("\"chat.layout\": \"columns\""))
    }
}
