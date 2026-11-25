// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import CoreSpotlight
import SwiftUI
import VelaCore
import VelaIntents
import VelaTheme

// The scene layer's half of Vela's automation: `vela://` links arriving as
// Apple events, Spotlight results arriving as user activities, and what
// links, AppleScript and Spotlight ask of the window (VelaIntents'
// `VelaAutomation` does the rest).

/// Bringing Vela to the front, which automation tests in demo mode turn off
/// (`--no-activate`), so they never take the focus from what you're doing.
@MainActor
enum AppActivation {
    static var isSuppressed = false

    static func activate() {
        guard !isSuppressed else { return }
        NSApp.activate()
    }
}

/// What links, AppleScript and Spotlight ask of the window.
@MainActor
final class AutomationPresenterBridge: AutomationPresenter {
    private let uiState: UIState

    init(uiState: UIState) {
        self.uiState = uiState
    }

    func activate() {
        ShowRequestRouter.shared?.bringForward()
    }

    func openSearch(_ request: MessageSearchRequest) {
        uiState.commandPalette = nil
        uiState.messageSearch = request
        activate()
    }

    func offerToJoin(_ channel: String, networkID: UUID) {
        uiState.joinChannelPrefill = channel
        uiState.joinChannelNetwork = networkID
        activate()
    }

    func notice(_ message: String) {
        uiState.automationNotice = AutomationNotice(message: message)
    }
}

/// A short notice at the top of the main window, such as why a `vela://`
/// link did nothing. It goes away by itself.
struct AutomationNotice: Equatable, Identifiable {
    let id = UUID()
    let message: String

    /// How long it stays.
    static let duration: Duration = .seconds(5)
}

// MARK: - Links

/// Receives `vela://` links (the "get URL" Apple event) for the whole app,
/// whether or not a window is open, and hands them to the link router.
///
/// SwiftUI installs a handler of its own for `onOpenURL`; this one is put
/// back once launching is done, so links never open a stray Recap window.
/// A link that launched Vela may reach SwiftUI's first: the main window's
/// `onOpenURL` passes it on, and the router ignores the same link twice.
@MainActor
final class LinkEventHandler: NSObject {
    let router: VelaLinkRouter
    private var observer: NSObjectProtocol?

    /// The running app's handler.
    static weak var shared: LinkEventHandler?

    init(router: VelaLinkRouter) {
        self.router = router
    }

    func install() {
        register()
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.register() }
        }
    }

    private func register() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let string = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: string)
        else { return }
        router.open(url)
    }
}

// MARK: - Spotlight results

/// Opens what was chosen in Spotlight: a message Vela indexed (scrolled to,
/// when it's still in the conversation's history), or "Search in Vela".
@MainActor
enum SpotlightActivity {
    static func open(_ activity: NSUserActivity, app: AppModel, uiState: UIState) {
        switch activity.activityType {
        case CSSearchableItemActionType:
            guard let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
                  let (bufferID, line) = SpotlightResults.message(forItemIdentifier: identifier)
            else { return }
            guard app.lookup(bufferID) != nil else {
                ShowRequestRouter.shared?.bringForward()
                uiState.automationNotice = AutomationNotice(message: "That conversation isn't open in Vela anymore.")
                return
            }
            app.requestShow(bufferID, line: line)
        case CSQueryContinuationActionType:
            guard let query = activity.userInfo?[CSSearchQueryString] as? String,
                  let automation = VelaAutomation.shared
            else { return }
            automation.search(query)
        default:
            break
        }
    }
}

// MARK: - Jumping to a message

/// Shows a message in its conversation: scrolls to it and highlights it,
/// loading older history first if it's further back than what's loaded.
@MainActor
enum MessageJump {
    static func jump(to line: LineReference, in buffer: BufferModel, session: NetworkSession, uiState: UIState) {
        if buffer.lines.contains(where: { $0.id == line.id }) {
            uiState.scrollTarget = line.id
            return
        }
        Task {
            for _ in 0..<30 {
                if buffer.lines.contains(where: { $0.id == line.id }) { break }
                guard buffer.hasMoreHistory, (buffer.lines.first?.time ?? .distantFuture) >= line.time else { break }
                if buffer.isLoadingHistory {
                    try? await Task.sleep(for: .milliseconds(100))
                    continue
                }
                await session.loadOlderHistory(for: buffer)
            }
            // Only a message that's there: a target that never turns up
            // would keep the list from landing where it should.
            if buffer.lines.contains(where: { $0.id == line.id }) {
                uiState.scrollTarget = line.id
            }
        }
    }
}

// MARK: - Notice

/// Shows ``UIState/automationNotice`` at the top of the main window.
struct AutomationNoticeOverlay: View {
    @Environment(UIState.self) private var uiState
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            if let notice = uiState.automationNotice {
                HStack(spacing: 8) {
                    Image(systemName: "link")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme[ThemeKey.accentText])
                        .accessibilityHidden(true)
                    Text(notice.message)
                        .font(.system(size: 12))
                        .foregroundStyle(theme[ThemeKey.popoverForeground])
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(theme[ThemeKey.popoverBackground]))
                .overlay(Capsule().strokeBorder(theme[ThemeKey.popoverBorder], lineWidth: 1))
                .devTag("Automation notice", tokens: [ThemeKey.popoverBackground, ThemeKey.popoverForeground, ThemeKey.popoverBorder])
                .padding(.top, PaletteMetrics.topInset)
                .padding(.horizontal, 24)
                .frame(maxWidth: 520)
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                .onTapGesture { uiState.automationNotice = nil }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isStaticText)
                .task(id: notice.id) {
                    AccessibilityNotification.Announcement(notice.message).post()
                    try? await Task.sleep(for: AutomationNotice.duration)
                    if uiState.automationNotice?.id == notice.id { uiState.automationNotice = nil }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: uiState.automationNotice)
    }
}
