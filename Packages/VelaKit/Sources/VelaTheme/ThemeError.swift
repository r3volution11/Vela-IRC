// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Problems loading, resolving or importing themes. Messages are written for
/// people editing theme files by hand.
public enum ThemeError: Error, LocalizedError, Sendable, Equatable {
    case unreadable(path: String, reason: String)
    case invalidJSON(String)
    case missingField(String)
    case invalidValue(path: String, message: String)
    case invalidColor(key: String, value: String)
    case includeNotFound(String)
    case includeCycle([String])
    case unsupportedFile(String)
    case notAVSCodeTheme(String)
    case vsixManifestMissing
    case vsixNoThemes
    case notAUserTheme(String)

    public var errorDescription: String? {
        switch self {
        case .unreadable(let path, let reason):
            "Couldn't read “\(path)”: \(reason)"
        case .invalidJSON(let message):
            "The file isn't valid JSON: \(message)"
        case .missingField(let field):
            "The required field “\(field)” is missing."
        case .invalidValue(let path, let message):
            "“\(path)”: \(message)"
        case .invalidColor(let key, let value):
            "“\(key)”: “\(value)” is not a hex color (use #RGB, #RGBA, #RRGGBB or #RRGGBBAA)."
        case .includeNotFound(let reference):
            "The included theme “\(reference)” wasn't found."
        case .includeCycle(let chain):
            "The themes include each other in a loop: \(chain.joined(separator: " → "))."
        case .unsupportedFile(let name):
            "“\(name)” isn't a theme file. Vela can import .json themes (Vela or VS Code) and .vsix extensions."
        case .notAVSCodeTheme(let name):
            "“\(name)” doesn't look like a VS Code color theme (it has no \"colors\" or \"tokenColors\")."
        case .vsixManifestMissing:
            "The extension has no extension/package.json."
        case .vsixNoThemes:
            "The extension doesn't contribute any JSON color themes."
        case .notAUserTheme(let name):
            "“\(name)” is a built-in theme and can't be changed or deleted."
        }
    }

    /// Converts JSON decoding failures into readable `ThemeError`s.
    static func from(decoding error: Error) -> ThemeError {
        if let error = error as? ThemeError { return error }
        guard let decodingError = error as? DecodingError else {
            return .invalidJSON(error.localizedDescription)
        }
        func path(_ codingPath: [CodingKey]) -> String {
            codingPath.map { key in key.intValue.map { "[\($0)]" } ?? key.stringValue }
                .joined(separator: ".")
                .replacingOccurrences(of: ".[", with: "[")
        }
        switch decodingError {
        case .keyNotFound(let key, let context):
            let parent = path(context.codingPath)
            return .missingField(parent.isEmpty ? key.stringValue : "\(parent).\(key.stringValue)")
        case .typeMismatch(let type, let context):
            return .invalidValue(path: path(context.codingPath), message: "expected \(describe(type)).")
        case .valueNotFound(let type, let context):
            return .invalidValue(path: path(context.codingPath), message: "expected \(describe(type)), found null.")
        case .dataCorrupted(let context):
            if context.codingPath.isEmpty {
                let underlying = (context.underlyingError as NSError?)?.userInfo[NSDebugDescriptionErrorKey] as? String
                return .invalidJSON(underlying ?? context.debugDescription)
            }
            return .invalidValue(path: path(context.codingPath), message: context.debugDescription)
        @unknown default:
            return .invalidJSON(String(describing: decodingError))
        }
    }

    private static func describe(_ type: Any.Type) -> String {
        switch type {
        case is String.Type: "a string"
        case is [String].Type: "an array of strings"
        case is [String: String].Type: "an object of strings"
        case is Double.Type, is Int.Type: "a number"
        case is Bool.Type: "true or false"
        default: "a different kind of value"
        }
    }
}
