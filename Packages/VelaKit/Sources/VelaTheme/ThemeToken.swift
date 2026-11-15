// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// How a token gets its value when a theme doesn't set it.
///
/// Operands are either hex literals (starting with `#`) or other token keys,
/// which is how fallback chains work: `memberList.background` defaults to
/// `ref("sidebar.background")`, which defaults to a mix of `window.background`.
public enum TokenDefault: Sendable, Hashable {
    /// A fixed color.
    case hex(String)
    /// The value of another token (or a hex literal).
    case ref(String)
    /// The operand with its alpha multiplied by the factor (VS Code semantics).
    case transparent(String, Double)
    /// `first` mixed toward `second` by `amount` (0 = first, 1 = second).
    case mix(String, String, Double)
    /// Black-ish or white, whichever reads better on the operand. Used for
    /// text drawn on accent-colored fills.
    case contrast(String)

    /// Token keys this default depends on.
    public var references: [String] {
        let operands: [String] = switch self {
        case .hex: []
        case .ref(let key): [key]
        case .transparent(let key, _): [key]
        case .mix(let first, let second, _): [first, second]
        case .contrast(let key): [key]
        }
        return operands.filter { !$0.hasPrefix("#") }
    }

    /// A compact, human-readable form used in docs and the JSON schema,
    /// e.g. `mix(window.background, #000000, 20%)`.
    public var expression: String {
        func percent(_ value: Double) -> String {
            let scaled = value * 100
            return scaled.rounded() == scaled ? "\(Int(scaled))%" : String(format: "%.1f%%", scaled)
        }
        return switch self {
        case .hex(let value): value
        case .ref(let key): key
        case .transparent(let key, let factor): "transparent(\(key), \(percent(factor)))"
        case .mix(let first, let second, let amount): "mix(\(first), \(second), \(percent(amount)))"
        case .contrast(let key): "contrast(\(key))"
        }
    }
}

/// One themable color.
public struct ThemeToken: Sendable, Hashable, Identifiable {
    public let key: String
    /// Registry section, e.g. `"sidebar"` or `"chat"`.
    public let group: String
    public let description: String
    public let dark: TokenDefault
    public let light: TokenDefault

    public var id: String { key }

    public init(key: String, group: String, description: String, dark: TokenDefault, light: TokenDefault) {
        self.key = key
        self.group = group
        self.description = description
        self.dark = dark
        self.light = light
    }

    public func defaultValue(for kind: ThemeKind) -> TokenDefault {
        kind == .dark ? dark : light
    }
}

/// A registry section, for grouping tokens in docs and the theme editor.
public struct ThemeTokenGroup: Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let description: String
}
