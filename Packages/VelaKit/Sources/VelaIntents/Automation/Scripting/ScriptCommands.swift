// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import Foundation
import VelaCore

// The commands of Vela's AppleScript dictionary (Vela/Vela.sdef). Each
// `NSScriptCommand` subclass only hands its arguments to
// ``ScriptCommandHandler``, which does the work through ``VelaAutomation``
// (the same code `vela://` links and the App Intents use) and is tested
// without Cocoa scripting.
//
// macOS asks you once per app before it can send Vela these ("“Raycast”
// wants access to control “Vela”"): that's the consent for sending
// messages, which links can never do.

/// Each command in the dictionary.
nonisolated public enum ScriptCommandKind: String, Sendable, CaseIterable {
    case show
    case sendMessage
    case draftMessage
    case join
    case catchUp
    case openRecap
    case markRead
    case markAllRead
    case search
    case setAway
    case setBack
}

/// The arguments' keys, as the sdef's `cocoa key`s name them.
nonisolated public enum ScriptArgument {
    public static let target = "Target"
    public static let allowMultipleLines = "AllowMultipleLines"
    public static let network = "Network"
    public static let key = "Key"
    public static let person = "Person"
    public static let span = "Span"
    public static let scope = "Scope"
}

/// What the commands do, apart from Cocoa scripting.
@MainActor
public enum ScriptCommandHandler {
    /// A command's result: ready now, or once some waiting is done (for a
    /// network that's connecting, a server confirming a join).
    public enum Outcome {
        case done(Any?)
        case later(@MainActor () async throws -> Any?)
    }

    /// Runs `kind` with its direct parameter (text, or an object the script
    /// named) and its other arguments, by `cocoa key`.
    public static func handle(_ kind: ScriptCommandKind, direct: Any?, arguments: [String: Any], automation: VelaAutomation) throws -> Outcome {
        switch kind {
        case .show:
            let (_, buffer) = try conversation(direct, automation)
            automation.show(buffer)
            return .done(nil)

        case .sendMessage:
            let text = try self.text(direct)
            let (session, buffer) = try conversation(arguments[ScriptArgument.target], automation)
            let allowsLines = (arguments[ScriptArgument.allowMultipleLines] as? NSNumber)?.boolValue ?? false
            return .later {
                try await automation.send(text, to: buffer, in: session, allowingMultipleLines: allowsLines)
                return nil
            }

        case .draftMessage:
            let raw = try self.text(direct)
            guard let text = VelaLink.cleanDraft(raw, maximumLength: .max) else { throw AutomationError.emptyMessage }
            guard text.count <= VelaLink.maximumDraftLength else {
                throw AutomationError.draftTooLong(text.count, limit: VelaLink.maximumDraftLength)
            }
            let (_, buffer) = try conversation(arguments[ScriptArgument.target], automation)
            automation.show(buffer, draft: text)
            return .done(nil)

        case .join:
            let channel = try self.text(direct)
            let session = try network(arguments[ScriptArgument.network], automation) ?? defaultJoinNetwork(automation)
            let key = (arguments[ScriptArgument.key] as? String).flatMap { $0.isEmpty ? nil : $0 }
            return .later {
                let buffer = try await automation.join(channel, on: session, key: key)
                return ScriptConversation(bufferID: buffer.id)
            }

        case .catchUp:
            let target: (session: NetworkSession, buffer: BufferModel)
            if direct == nil {
                guard let busiest = automation.busiestUnread else { return .done(nil) }
                target = busiest
            } else {
                target = try conversation(direct, automation)
            }
            try automation.openCatchUp(target.buffer, session: target.session)
            return .done(nil)

        case .openRecap:
            var conversationID: BufferID?
            var networkID: UUID?
            if let direct {
                if let session = try? network(direct, automation) {
                    networkID = session.id
                } else {
                    conversationID = try conversation(direct, automation).buffer.id
                }
            }
            let person = (arguments[ScriptArgument.person] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let span = (arguments[ScriptArgument.span] as? NSNumber).flatMap { ScriptCode.spans[$0.uint32Value] } ?? .sinceUnread
            let scope = automation.recapScope(conversation: conversationID, network: networkID, person: person, span: span)
            try automation.openRecap(scope)
            return .done(nil)

        case .markRead:
            let (session, buffer) = try conversation(direct, automation)
            automation.markRead(buffer, in: session)
            return .done(nil)

        case .markAllRead:
            return .done(automation.markAllRead())

        case .search:
            let raw = try self.text(direct)
            guard let query = VelaLink.cleanQuery(raw, maximumLength: .max) else { throw AutomationError.emptyMessage }
            guard query.count <= VelaLink.maximumQueryLength else {
                throw AutomationError.queryTooLong(query.count, limit: VelaLink.maximumQueryLength)
            }
            let scope = arguments[ScriptArgument.scope]
            if scope == nil {
                automation.search(query)
            } else if let session = try? network(scope, automation) {
                automation.search(query, networkID: session.id)
            } else {
                automation.search(query, bufferID: try conversation(scope, automation).buffer.id)
            }
            return .done(nil)

        case .setAway:
            let message = (direct as? String).flatMap { $0.isEmpty ? nil : $0 }
            return .later { try await automation.setAway(message) }

        case .setBack:
            return .later { try await automation.setBack() }
        }
    }

    // MARK: Arguments

    private static func text(_ value: Any?) throws -> String {
        guard let text = value as? String else { throw AutomationError.emptyMessage }
        return text
    }

    /// The one conversation `value` names: an object the script named, or
    /// its name as text.
    static func conversation(_ value: Any?, _ automation: VelaAutomation) throws -> (session: NetworkSession, buffer: BufferModel) {
        switch value {
        case let conversation as ScriptConversation:
            guard let target = automation.app.lookup(conversation.bufferID), target.buffer.kind != .server else {
                throw AutomationError.unknownConversation(conversation.bufferID.foldedName)
            }
            return target
        case let list as [Any]:
            guard list.count == 1 else { throw AutomationError.ambiguousConversation("more than one conversation") }
            return try conversation(list[0], automation)
        case let name as String:
            guard let buffer = ScriptLookup.conversation(named: name, in: automation.app),
                  let session = automation.app.session(for: buffer.id.networkID)
            else { throw AutomationError.unknownConversation(name) }
            return (session, buffer)
        case let specifier as NSScriptObjectSpecifier:
            // One that didn't evaluate: there's no such conversation.
            guard let object = specifier.objectsByEvaluatingSpecifier else {
                throw AutomationError.unknownConversation("that conversation")
            }
            return try conversation(object, automation)
        default:
            throw AutomationError.unknownConversation("that conversation")
        }
    }

    /// The network `value` names, if any: an object the script named, or a
    /// name or id as text. Throws for something that isn't a network.
    static func network(_ value: Any?, _ automation: VelaAutomation) throws -> NetworkSession? {
        switch value {
        case nil:
            return nil
        case let network as ScriptNetwork:
            guard let session = automation.app.session(for: network.networkID) else {
                throw AutomationError.unknownNetwork(network.uniqueID)
            }
            return session
        case let list as [Any] where list.count == 1:
            return try self.network(list[0], automation)
        case let name as String:
            return try automation.network(name)
        case let specifier as NSScriptObjectSpecifier:
            return try self.network(specifier.objectsByEvaluatingSpecifier, automation)
        default:
            throw AutomationError.unknownNetwork("that network")
        }
    }

    /// Where `join` goes without a network: the one you're looking at, else
    /// the only one you're connected to.
    private static func defaultJoinNetwork(_ automation: VelaAutomation) throws -> NetworkSession {
        let app = automation.app
        if let selected = app.selectedSession, app.automationSessions.contains(where: { $0 === selected }), !selected.isBouncerControl {
            return selected
        }
        let connected = app.automationSessions.filter { $0.isConnected && !$0.isBouncerControl }
        if connected.count == 1 { return connected[0] }
        throw AutomationError.needsNetwork
    }
}

// MARK: - Cocoa scripting

/// Holds a value across an `await` on the main actor, where Swift can't
/// see that it stays there.
nonisolated private final class MainThreadBox<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}

/// The base of every command class the sdef names.
nonisolated public class VelaScriptCommand: NSScriptCommand {
    /// Which command this class is.
    class var kind: ScriptCommandKind { fatalError("Subclasses say which command they are.") }

    /// A command with no object to act on (or text as its direct
    /// parameter): the application's.
    public override func performDefaultImplementation() -> Any? {
        perform(direct: evaluatedReceivers ?? directParameter)
    }

    /// Runs the command on `direct`: the object a script named, which
    /// Cocoa scripting hands to it (``ScriptConversation/handleVelaScriptCommand(_:)``),
    /// or the direct parameter.
    func perform(direct: Any?) -> Any? {
        let kind = Self.kind
        // Cocoa scripting runs commands on the main thread.
        let input = MainThreadBox((direct: direct, arguments: (evaluatedArguments ?? [:]) as [String: Any], command: self as NSScriptCommand))
        nonisolated(unsafe) var value: Any?
        MainActor.assumeIsolated {
            value = Self.run(kind, direct: input.value.direct, arguments: input.value.arguments, command: input.value.command)
        }
        return value
    }

    @MainActor
    private static func run(_ kind: ScriptCommandKind, direct: Any?, arguments: [String: Any], command: NSScriptCommand) -> Any? {
        guard let automation = VelaAutomation.shared else {
            command.fail(AutomationError.notReady)
            return nil
        }
        // A script that just launched Vela: start it if the window hasn't
        // yet, and wait for its networks and conversations to be restored,
        // as Siri does, then run.
        automation.app.start()
        guard automation.app.isReady else {
            let input = MainThreadBox((direct: direct, arguments: arguments))
            finishLater(command) {
                await automation.app.ready()
                switch try ScriptCommandHandler.handle(kind, direct: input.value.direct, arguments: input.value.arguments, automation: automation) {
                case .done(let value): return value
                case .later(let work): return try await work()
                }
            }
            return nil
        }
        do {
            switch try ScriptCommandHandler.handle(kind, direct: direct, arguments: arguments, automation: automation) {
            case .done(let value):
                return value
            case .later(let work):
                finishLater(command, work)
                return nil
            }
        } catch {
            command.fail(error)
            return nil
        }
    }

    /// Suspends `command` while `work` runs, without holding up the main
    /// thread; AppleScript gets its answer when the work is done.
    @MainActor
    private static func finishLater(_ command: NSScriptCommand, _ work: @escaping @MainActor () async throws -> Any?) {
        command.suspendExecution()
        let box = MainThreadBox(command)
        Task { @MainActor in
            do {
                let value = try await work()
                box.value.resumeExecution(withResult: value)
            } catch {
                box.value.fail(error)
                box.value.resumeExecution(withResult: nil)
            }
        }
    }
}

extension NSScriptCommand {
    /// Reports `error` to the script: Vela's number and words for its own
    /// errors (``AutomationError/scriptErrorNumber``).
    nonisolated func fail(_ error: any Error) {
        let wrapped = AutomationError.wrapping(error)
        if let automation = wrapped as? AutomationError {
            scriptErrorNumber = automation.scriptErrorNumber
            scriptErrorString = automation.errorDescription
        } else {
            scriptErrorNumber = -2700  // errOSAGeneralError
            scriptErrorString = wrapped.localizedDescription
        }
    }
}

@objc(VelaShowCommand)
nonisolated public final class VelaShowCommand: VelaScriptCommand {
    override class var kind: ScriptCommandKind { .show }
}

@objc(VelaSendMessageCommand)
nonisolated public final class VelaSendMessageCommand: VelaScriptCommand {
    override class var kind: ScriptCommandKind { .sendMessage }
}

@objc(VelaDraftMessageCommand)
nonisolated public final class VelaDraftMessageCommand: VelaScriptCommand {
    override class var kind: ScriptCommandKind { .draftMessage }
}

@objc(VelaJoinCommand)
nonisolated public final class VelaJoinCommand: VelaScriptCommand {
    override class var kind: ScriptCommandKind { .join }
}

@objc(VelaCatchUpCommand)
nonisolated public final class VelaCatchUpCommand: VelaScriptCommand {
    override class var kind: ScriptCommandKind { .catchUp }
}

@objc(VelaOpenRecapCommand)
nonisolated public final class VelaOpenRecapCommand: VelaScriptCommand {
    override class var kind: ScriptCommandKind { .openRecap }
}

@objc(VelaMarkReadCommand)
nonisolated public final class VelaMarkReadCommand: VelaScriptCommand {
    override class var kind: ScriptCommandKind { .markRead }
}

@objc(VelaMarkAllReadCommand)
nonisolated public final class VelaMarkAllReadCommand: VelaScriptCommand {
    override class var kind: ScriptCommandKind { .markAllRead }
}

@objc(VelaSearchCommand)
nonisolated public final class VelaSearchCommand: VelaScriptCommand {
    override class var kind: ScriptCommandKind { .search }
}

@objc(VelaSetAwayCommand)
nonisolated public final class VelaSetAwayCommand: VelaScriptCommand {
    override class var kind: ScriptCommandKind { .setAway }
}

@objc(VelaSetBackCommand)
nonisolated public final class VelaSetBackCommand: VelaScriptCommand {
    override class var kind: ScriptCommandKind { .setBack }
}

/// Vela's scripting classes, by the names the sdef gives them.
public enum ScriptingSupport {
    /// Every class the sdef names, so the linker keeps them all (Cocoa
    /// scripting finds them by name) and tests can check the names.
    public nonisolated static let classes: [AnyClass] = [
        ScriptNetwork.self, ScriptConversation.self,
        VelaShowCommand.self, VelaSendMessageCommand.self, VelaDraftMessageCommand.self, VelaJoinCommand.self,
        VelaCatchUpCommand.self, VelaOpenRecapCommand.self, VelaMarkReadCommand.self, VelaMarkAllReadCommand.self,
        VelaSearchCommand.self, VelaSetAwayCommand.self, VelaSetBackCommand.self,
    ]

    /// Makes the scripting classes known to the Objective-C runtime before
    /// the first Apple event arrives. Call once at launch.
    @MainActor
    public static func register(_ automation: VelaAutomation) {
        VelaAutomation.shared = automation
        for type in classes { _ = NSStringFromClass(type) }
    }
}
