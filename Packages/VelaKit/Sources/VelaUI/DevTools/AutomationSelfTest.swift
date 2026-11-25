// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

#if DEBUG
import AppKit
import Foundation
import VelaCore
import VelaIntents

/// `--automation-self-test`, for Vela Dev in demo mode only: drives Vela's
/// AppleScript dictionary (Vela.sdef, through Cocoa scripting, as a script
/// would) and a `vela-dev://` link (through Launch Services) from inside
/// the app, where macOS asks no Automation permission, and writes what
/// happened to `tmp/AutomationSelfTest.txt` in Vela Dev's container. Run it
/// with `--no-activate` so nothing takes the focus:
///
///     open -g -n "build/DerivedData/Build/Products/Debug/Vela.app" --args --demo --no-activate --automation-self-test
///     cat ~/Library/Containers/io.github.r3volution11.Vela.dev/Data/tmp/AutomationSelfTest.txt
///
/// Not in release builds.
@MainActor
enum AutomationSelfTest {
    static func scheduleIfAsked(app: AppModel) {
        guard app.isDemo, ProcessInfo.processInfo.arguments.contains("--automation-self-test") else { return }
        Task { @MainActor in
            // Let the window and the scripting dictionary load first.
            try? await Task.sleep(for: .seconds(3))
            await run(app: app)
        }
    }

    static var reportURL: URL { FileManager.default.temporaryDirectory.appending(path: "AutomationSelfTest.txt") }

    private static func run(app: AppModel) async {
        var report = ["Automation self-test, \(Date().formatted(date: .numeric, time: .standard))", ""]
        let bundle = Bundle.main.bundleURL.path

        // Through AppleScript, in this process ("current application").
        func script(_ body: String) -> String {
            let source = """
                using terms from application "\(bundle)"
                    tell current application
                        set AppleScript's text item delimiters to ", "
                        \(body)
                    end tell
                end using terms from
                """
            var error: NSDictionary?
            guard let result = NSAppleScript(source: source)?.executeAndReturnError(&error) else {
                return "ERROR \(error?[NSAppleScript.errorNumber] ?? "?"): \(error?[NSAppleScript.errorMessage] ?? "")"
            }
            return result.stringValue ?? "(\(result.descriptorType))"
        }
        let checks: [(String, String)] = [
            ("name, version", "return (name as text) & \" \" & (version as text)"),
            ("networks", "return (name of every network) as text"),
            ("count of networks", "return (count of networks) as text"),
            ("network by name", "return (connected of network \"oftc\") as text"),
            ("network id round trip", "return name of network id (id of network \"Libera.Chat\")"),
            ("conversations of Libera.Chat", "return (name of every conversation of network \"Libera.Chat\") as text"),
            ("conversation id", "return id of conversation \"#vela\" of network \"Libera.Chat\""),
            ("by id", "return name of conversation id (id of conversation \"#ergo\")"),
            ("kind", "return (kind of conversation \"marisol\") as text"),
            ("properties", "set c to conversation \"#vela\"\nreturn (get network name of c) & \" joined:\" & (get joined of c) & \" muted:\" & (get muted of c) & \" unread:\" & (get unread count of c) & \" mentions:\" & (get mention count of c) & \" topic:\" & (get topic of c)"),
            ("network of conversation", "return name of network of conversation \"#debian\""),
            ("unread conversations", "return (get name of unread conversations) as text"),
            ("each unread conversation", "set out to {}\nrepeat with c in (get unread conversations)\nset end of out to (get name of c)\nend repeat\nreturn out as text"),
            ("whose mention count > 0", "return (name of (conversations whose mention count > 0)) as text"),
            ("current conversation", "return name of current conversation"),
            ("exists (no)", "return (exists conversation \"#nowhere\") as text"),
            ("unknown conversation", "try\nget name of conversation id \"nope\"\non error number n\nreturn n as text\nend try"),
            ("show", "show conversation \"#swift\"\nreturn name of current conversation"),
            ("draft message", "draft message \"drafted by the self-test\" to conversation \"#vela-offtopic\"\nreturn name of current conversation"),
            ("mark read", "mark read conversation \"#swift\"\nreturn (unread count of conversation \"#swift\") as text"),
            ("mark all read", "return (mark all read) as text"),
            ("catch up", "catch up conversation \"#vela\"\nreturn name of current conversation"),
            ("search", "search \"aurora\" on network \"Libera.Chat\"\nreturn \"opened\""),
            ("open recap", "open recap network \"Libera.Chat\" person \"wren\" span today\nreturn \"opened\""),
            ("draft to nowhere", "try\ndraft message \"x\" to conversation \"#nowhere\"\non error m number n\nreturn (n as text) & \" \" & m\nend try"),
        ]
        for (name, body) in checks {
            report.append("\(name): \(script(body))")
        }

        // Commands that wait, as Apple events. Sent to this process, an event
        // is handled right away on the sending thread, so they go from the
        // main thread and what they did is read from the model.
        let libera = app.sessions.first { $0.displayName == "Libera.Chat" }
        let waiting: [(String, NSAppleEventDescriptor, @MainActor () -> String)] = [
            ("send message", event("VelaSend", direct: .init(string: "hello from the self-test"), ["VsTo": specifier(conversation: "#vela")]), {
                "last line in #vela: " + (libera?.buffer(named: "#vela")?.lines.last.map { "\($0.nick ?? "") \($0.text)" } ?? "none")
            }),
            ("send message, 4 lines (refused)", event("VelaSend", direct: .init(string: "1\n2\n3\n4"), ["VsTo": specifier(conversation: "#swift")]), {
                "last line in #swift: " + (libera?.buffer(named: "#swift")?.lines.last?.text ?? "none")
            }),
            ("join", event("VelaJoin", direct: .init(string: "#selftest"), [:]), {
                let buffer = libera?.buffer(named: "#selftest")
                return "#selftest exists: \(buffer != nil), joined: \(buffer?.isJoined ?? false)"
            }),
            ("set away", event("VelaAway", direct: .init(string: "testing"), [:]), { "sent" }),
            ("set back", event("VelaBack", direct: nil, [:]), { "sent" }),
        ]
        for (name, event, check) in waiting {
            // Sent to itself, a command that waits can't answer while the
            // main thread is in this call: the send times out, and the
            // command finishes once it returns.
            let reply: String
            do {
                _ = try event.sendEvent(options: [.noReply], timeout: 1)
                reply = "sent"
            } catch {
                reply = "no reply (\((error as NSError).code))"
            }
            try? await Task.sleep(for: .seconds(2))
            report.append("\(name): \(reply); \(check())")
        }

        // A link, through Launch Services, without activating Vela.
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        for link in ["vela-dev://open?network=OFTC&channel=%23debian", "vela-dev://open?channel=%23nowhere"] {
            _ = try? await NSWorkspace.shared.open(URL(string: link)!, configuration: configuration)
            try? await Task.sleep(for: .seconds(2))
            report.append("link \(link): current conversation is \(script("return name of current conversation"))")
        }

        report += ["", "done"]
        try? report.joined(separator: "\n").write(to: reportURL, atomically: true, encoding: .utf8)
    }

    // MARK: Raw events

    private static func code(_ string: String) -> FourCharCode {
        string.utf8.reduce(0) { ($0 << 8) | FourCharCode($1) }
    }

    /// `conversation "<name>"` of the application, as an event parameter.
    private static func specifier(conversation name: String) -> NSAppleEventDescriptor {
        let application = NSScriptClassDescription(for: NSApplication.self)!
        return NSNameSpecifier(containerClassDescription: application, containerSpecifier: nil, key: "velaConversations", name: name).descriptor!
    }

    private static func event(_ name: String, direct: NSAppleEventDescriptor?, _ parameters: [String: NSAppleEventDescriptor]) -> NSAppleEventDescriptor {
        let target = NSAppleEventDescriptor(processIdentifier: ProcessInfo.processInfo.processIdentifier)
        let codes = Array(name.utf8)
        let eventClass = codes[0..<4].reduce(FourCharCode(0)) { ($0 << 8) | FourCharCode($1) }
        let eventID = codes[4..<8].reduce(FourCharCode(0)) { ($0 << 8) | FourCharCode($1) }
        let event = NSAppleEventDescriptor(eventClass: eventClass, eventID: eventID, targetDescriptor: target, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        if let direct { event.setParam(direct, forKeyword: AEKeyword(keyDirectObject)) }
        for (key, value) in parameters { event.setParam(value, forKeyword: code(key)) }
        return event
    }
}
#endif
