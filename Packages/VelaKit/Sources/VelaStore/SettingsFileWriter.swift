// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaFoundation

/// Turns settings changes into minimal edits of settings.json's text, so
/// comments and formatting survive changes made in the app.
enum SettingsFileWriter {
    /// One top-level change: a new value, or nil to remove the key.
    typealias Change = (key: String, value: JSONValue?)

    /// `text` with `changes` applied as minimal edits.
    ///
    /// - Changes apply in key order; a new key is appended after the last
    ///   property of the top-level object.
    /// - Objects are compared member by member, so only the members that
    ///   changed are touched (comments inside `appearance.colorCustomizations`
    ///   or `media.siteRules` survive). Arrays and other values are replaced
    ///   whole when they differ.
    /// - Blank text gets a fresh pretty-printed object holding `fullValues`.
    static func text(applying changes: [Change], to text: String, fullValues: [String: JSONValue]) throws -> String {
        let document = JSONCDocument(text)
        let format = JSONCFormat(detectingIn: document)
        if document.root == nil, document.errors.isEmpty,
           document.tokens.allSatisfy({ $0.kind == .whitespace || $0.kind == .lineBreak })
        {
            guard !fullValues.isEmpty else { return text }
            return JSONCEditing.format(.object(fullValues), format: format) + format.lineEnding
        }

        var text = text
        for change in changes.sorted(by: { $0.key < $1.key }) {
            let current = JSONCDocument(text)
            let operations = diff(
                path: [change.key],
                node: current.root?.lastProperty(named: change.key)?.value,
                exists: current.root?.lastProperty(named: change.key) != nil,
                desired: change.value
            )
            for operation in operations {
                text = try JSONCEditing.setting(operation.value, at: operation.path, in: text, format: format)
            }
        }
        return text
    }

    /// The path-level sets and removals that turn `node` into `desired`.
    static func diff(path: [String], node: JSONCNode?, exists: Bool, desired: JSONValue?) -> [(path: [String], value: JSONValue?)] {
        guard let desired else { return exists ? [(path, nil)] : [] }
        guard let node, let current = node.jsonValue else { return [(path, desired)] }
        guard current != desired else { return [] }
        guard node.kind == .object, node.isClosed, case .object(let wanted) = desired else {
            return [(path, desired)]
        }
        var operations: [(path: [String], value: JSONValue?)] = []
        var removed = Set<String>()
        for property in node.properties where wanted[property.key] == nil && removed.insert(property.key).inserted {
            operations.append((path + [property.key], nil))
        }
        for key in wanted.keys.sorted() {
            let property = node.lastProperty(named: key)
            operations += diff(path: path + [key], node: property?.value, exists: property != nil, desired: wanted[key])
        }
        return operations
    }
}
