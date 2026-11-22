// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import Foundation
import Testing
@testable import VelaIntents

/// Vela/Vela.sdef against the code it names: it's valid, every class and
/// key it names exists, and every command and code matches. Alfred and
/// Raycast build on this dictionary, so a typo here would break them
/// silently, only when a script runs.
@Suite("AppleScript dictionary")
struct ScriptingDictionaryTests {
    /// Vela/Vela.sdef, from this file's place in the repository.
    static let sdefURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // VelaIntentsTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // VelaKit
        .deletingLastPathComponent()  // Packages
        .deletingLastPathComponent()  // repository
        .appending(path: "Vela/Vela.sdef")

    private func document() throws -> XMLDocument {
        try XMLDocument(contentsOf: Self.sdefURL, options: [])
    }

    private func nodes(_ xpath: String) throws -> [XMLElement] {
        try document().nodes(forXPath: xpath).compactMap { $0 as? XMLElement }
    }

    private func attribute(_ element: XMLElement, _ name: String) -> String? {
        element.attribute(forName: name)?.stringValue
    }

    /// Valid against the system's sdef DTD (the same check as `xmllint`).
    @Test func isValidAgainstTheDTD() throws {
        let document = try document()
        try document.validate()
    }

    @Test func everyCocoaClassExists() throws {
        for element in try nodes("//cocoa[@class]") {
            let name = try #require(attribute(element, "class"))
            #expect(NSClassFromString(name) != nil, "No class named \(name)")
        }
    }

    /// Each scriptable class answers to every key the sdef reads from it.
    @Test func everyCocoaKeyIsAnswered() throws {
        let classes: [String: NSObject.Type] = [
            "network": ScriptNetwork.self,
            "conversation": ScriptConversation.self,
            "application": NSApplication.self,
        ]
        for container in try nodes("//class | //class-extension") {
            let name = attribute(container, "name") ?? attribute(container, "extends") ?? ""
            guard let type = classes[name] else { continue }
            for member in container.elements(forName: "property") + container.elements(forName: "element") {
                let key = member.elements(forName: "cocoa").first.flatMap { attribute($0, "key") }
                    ?? attribute(member, "name") ?? ""
                // Cocoa's own application properties (name, version) come
                // from AppKit's scripting support.
                if name == "application", ["name", "version", "isActive"].contains(key) { continue }
                #expect(type.instancesRespond(to: Selector(key)), "\(name) has no key \(key)")
            }
        }
    }

    /// Each command class is the command its sdef entry describes.
    @Test func commandsMatchTheirClasses() throws {
        let kinds: [String: ScriptCommandKind] = [
            "show": .show, "send message": .sendMessage, "draft message": .draftMessage, "join": .join,
            "catch up": .catchUp, "open recap": .openRecap, "mark read": .markRead, "mark all read": .markAllRead,
            "search": .search, "set away": .setAway, "set back": .setBack,
        ]
        var seen: Set<ScriptCommandKind> = []
        for command in try nodes("//suite[@name='Vela Suite']/command") {
            let name = try #require(attribute(command, "name"))
            let className = try #require(command.elements(forName: "cocoa").first.flatMap { attribute($0, "class") })
            let type = try #require(NSClassFromString(className) as? VelaScriptCommand.Type, "\(className) isn't a Vela command")
            let kind = try #require(kinds[name], "Unknown command \(name)")
            #expect(type.kind == kind, "\(name) runs \(type.kind)")
            #expect(attribute(command, "code")?.utf8.count == 8)
            seen.insert(kind)
        }
        #expect(seen == Set(ScriptCommandKind.allCases))
    }

    /// A command whose direct parameter can be a network or a conversation
    /// is in that class's responds-to list, handled by the method the
    /// class has: otherwise Cocoa scripting answers "doesn't understand"
    /// (-1708) instead of running it.
    @Test func objectCommandsAreRespondedTo() throws {
        let classes: [String: NSObject.Type] = ["network": ScriptNetwork.self, "conversation": ScriptConversation.self]
        for command in try nodes("//suite[@name='Vela Suite']/command") {
            let name = try #require(attribute(command, "name"))
            guard let direct = command.elements(forName: "direct-parameter").first else { continue }
            let types = [attribute(direct, "type")].compactMap { $0 } + direct.elements(forName: "type").compactMap { attribute($0, "type") }
            for type in types {
                guard let objectClass = classes[type] else { continue }
                let respondsTo = try nodes("//class[@name='\(type)']/responds-to[@command='\(name)']/cocoa")
                let method = try #require(respondsTo.first.flatMap { attribute($0, "method") }, "\(type) doesn't respond to \(name)")
                #expect(objectClass.instancesRespond(to: Selector(method)), "\(type) has no \(method)")
            }
        }
    }

    /// The argument keys the handler reads are the ones the sdef passes.
    @Test func argumentKeysMatch() throws {
        let keys = Set(try nodes("//suite[@name='Vela Suite']/command/parameter/cocoa").compactMap { attribute($0, "key") })
        #expect(keys == [
            ScriptArgument.target, ScriptArgument.allowMultipleLines, ScriptArgument.network, ScriptArgument.key,
            ScriptArgument.person, ScriptArgument.span, ScriptArgument.scope,
        ])
    }

    @Test func enumerationCodesMatch() throws {
        var codes: [String: String] = [:]
        for enumerator in try nodes("//enumerator") {
            codes[attribute(enumerator, "name") ?? ""] = attribute(enumerator, "code")
        }
        #expect(codes["channel"].map(ScriptCode.of) == ScriptCode.channel)
        #expect(codes["private conversation"].map(ScriptCode.of) == ScriptCode.privateConversation)
        let spans: [String: RecapSpanOption] = [
            "since unread": .sinceUnread, "last half hour": .lastHalfHour, "last hour": .lastHour, "last four hours": .lastFourHours,
            "today": .today, "last day": .lastDay, "last three days": .lastThreeDays, "last week": .lastWeek,
        ]
        for (name, span) in spans {
            let code = try #require(codes[name], "No enumerator \(name)")
            #expect(ScriptCode.spans[ScriptCode.of(code)] == span, "\(name)")
        }
        #expect(ScriptCode.spans.count == spans.count)
    }

    /// Four-character codes are unique where they must be: classes,
    /// commands, and the Vela suite's properties (except the standard
    /// "ID  " and "pnam", which every class shares).
    @Test func codesAreUnique() throws {
        let classCodes = try nodes("//class").compactMap { attribute($0, "code") }
        #expect(Set(classCodes).count == classCodes.count)
        let commandCodes = try nodes("//command").compactMap { attribute($0, "code") }
        #expect(Set(commandCodes).count == commandCodes.count)
        var propertyCodes: [String: String] = [:]
        for property in try nodes("//suite[@name='Vela Suite']//property") {
            guard let code = attribute(property, "code"), !["ID  ", "pnam"].contains(code) else { continue }
            let name = attribute(property, "name") ?? ""
            if let other = propertyCodes[code] { #expect(other == name, "\(code) is both \(other) and \(name)") }
            propertyCodes[code] = name
        }
    }

    /// Info.plist (releases) and Config/Debug-Info.plist (Vela Dev) both
    /// name the dictionary and register a link scheme each.
    @Test func infoPlistsDeclareTheDictionaryAndLinks() throws {
        let repository = Self.sdefURL.deletingLastPathComponent().deletingLastPathComponent()
        for (path, scheme) in [("Vela/Info.plist", "vela"), ("Config/Debug-Info.plist", "vela-dev")] {
            let data = try Data(contentsOf: repository.appending(path: path))
            let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
            #expect(plist["OSAScriptingDefinition"] as? String == "Vela.sdef", "\(path)")
            #expect(plist["NSAppleScriptEnabled"] as? Bool == true, "\(path)")
            let types = try #require(plist["CFBundleURLTypes"] as? [[String: Any]], "\(path)")
            #expect(types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] } == [scheme], "\(path)")
            #expect(VelaLink.schemes.contains(scheme))
        }
    }
}
