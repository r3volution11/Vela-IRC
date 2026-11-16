// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaFoundation
import VelaCore
import VelaStore

/// Launch arguments for demo mode, handy for screenshots and UI work:
///
///     Vela --demo --theme "Lighter" --preset tabbed --set chat.layout=classic --set tabs.roundness=1
///
/// `--set` values are parsed as JSON when possible (numbers, booleans,
/// arrays), otherwise used as strings.
enum DemoArguments {
    @MainActor
    static func apply(_ arguments: [String], to settings: SettingsStore) {
        var iterator = arguments.makeIterator()
        while let argument = iterator.next() {
            switch argument {
            case "--theme":
                guard let name = iterator.next() else { continue }
                settings[.appearanceFollowSystem] = false
                settings[.appearanceTheme] = name
            case "--preset":
                guard let id = iterator.next(), let preset = SettingsPreset.all.first(where: { $0.id == id }) else { continue }
                settings.apply(preset)
            case "--select":
                // Handled by `selectBuffer(from:in:)` once sessions exist.
                _ = iterator.next()
            case "--set":
                guard let pair = iterator.next(), let eq = pair.firstIndex(of: "=") else { continue }
                let key = String(pair[..<eq])
                let raw = String(pair[pair.index(after: eq)...])
                let value = (try? JSONC.value(from: Data(raw.utf8))) ?? .string(raw)
                settings.setValue(value, forKey: key)
            default:
                continue
            }
        }
    }

    /// `--select "#ergo"` or `--select "OFTC/#debian"` picks the initial buffer.
    @MainActor
    static func selectBuffer(from arguments: [String], in app: AppModel) {
        guard let index = arguments.firstIndex(of: "--select"), arguments.indices.contains(index + 1) else { return }
        let spec = arguments[index + 1]
        let parts = spec.split(separator: "/", maxSplits: 1).map(String.init)
        let (networkName, bufferName) = parts.count == 2 ? (parts[0], parts[1]) : (nil, parts[0])
        for session in app.sessions where networkName.map({ session.displayName.caseInsensitiveCompare($0) == .orderedSame }) ?? true {
            if let buffer = session.buffer(named: bufferName) ?? (bufferName == "*" ? session.serverBuffer : nil) {
                app.select(buffer)
                return
            }
        }
    }
}
