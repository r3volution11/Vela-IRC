// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import VelaCore
import VelaIntelligence
import VelaStore
import VelaTheme

/// A Recap window: a report on its scope, drawn in the app's theme like a
/// document. The top bar has the title and Stop, Regenerate, Copy and
/// Save; the bar under it says what the Recap covers (Who, Where, When)
/// and how it's shown (Summary or Log). Nothing in it is saved: closing
/// the window stops the summary and forgets the report.
///
/// The window keeps the value it was opened for (opening that Recap again
/// brings it forward); changing what it covers changes the session, not
/// the value, so SwiftUI never rebuilds the window under a running summary.
struct RecapWindowView: View {
    @Environment(AppModel.self) private var app
    @Environment(IntelligenceServices.self) private var intelligence
    @Binding var value: RecapWindowValue?

    @State private var session: RecapSession?
    @State private var choosesPerson = false

    var body: some View {
        Group {
            if let session {
                RecapWindowContent(session: session, choosesPerson: $choosesPerson)
            } else {
                Color.clear
            }
        }
        .onAppear(perform: begin)
        .onDisappear { session?.close() }
    }

    private func begin() {
        guard session == nil, let value else { return }
        choosesPerson = value.choosesPerson
        let session = Self.makeSession(value.scope, app: app, intelligence: intelligence)
        self.session = session
        session.start()
    }

    /// A session reading `app`'s messages and writing with `intelligence`.
    static func makeSession(_ scope: RecapScope, app: AppModel, intelligence: IntelligenceServices) -> RecapSession {
        let gatherer = RecapGatherer(app: app)
        let previews = app.previewService
        return RecapSession(
            scope: scope,
            gather: { await gatherer.gather($0) },
            summarizer: intelligence.recapSummarizer,
            status: { intelligence.availability.status },
            linkTitles: { urls in
                var titles: [URL: String] = [:]
                for url in urls {
                    if let title = await previews.cachedPreview(for: url)?.title?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !title.isEmpty {
                        titles[url] = title
                    }
                }
                return titles
            }
        )
    }
}

/// A Recap window's content for demo screenshots (`--recap`): canned
/// results, started at once, and More detail opened on the first topic
/// with `--recap-detail`.
struct RecapSnapshotView: View {
    @Environment(AppModel.self) private var app
    @Environment(IntelligenceServices.self) private var intelligence
    let scope: RecapScope
    let expandsDetail: Bool

    @State private var session: RecapSession?
    @State private var choosesPerson = false

    var body: some View {
        Group {
            if let session {
                RecapWindowContent(session: session, choosesPerson: $choosesPerson)
            } else {
                Color.clear
            }
        }
        .task {
            let session = RecapWindowView.makeSession(scope, app: app, intelligence: intelligence)
            self.session = session
            session.start()
            guard expandsDetail else { return }
            for _ in 0..<200 where session.summaryPhase != .done {
                try? await Task.sleep(for: .milliseconds(50))
            }
            if let topic = session.summary?.topics.first { session.moreDetail(on: topic) }
        }
    }
}

/// The window's bars and document, for one session.
struct RecapWindowContent: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @Bindable var session: RecapSession
    @Binding var choosesPerson: Bool

    var body: some View {
        let title = RecapActions.title(for: session.scope, app: app)
        VStack(spacing: 0) {
            RecapTopBar(session: session, title: title)
            Rectangle().fill(theme[ThemeKey.titleBarBorder]).frame(height: 1)
            RecapScopeBar(session: session, choosesPerson: $choosesPerson)
            Rectangle().fill(theme[ThemeKey.titleBarBorder]).frame(height: 1)
            RecapDocumentView(session: session, title: title)
        }
        .ignoresSafeArea(.container, edges: .top)
        .themedWindowBorder()
        .background(theme[ThemeKey.chatBackground])
        .background(ThemedWindowConfigurator(theme: theme, backgroundKey: ThemeKey.chatBackground, title: title, tallTitleBar: true))
        .frame(minWidth: 600, idealWidth: 780, minHeight: 440, idealHeight: 820)
    }
}

// MARK: - Top bar

/// The title, and Stop, Regenerate, Copy and Save as Markdown….
private struct RecapTopBar: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    let session: RecapSession
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme[ThemeKey.accent])
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme[ThemeKey.titleBarForeground])
                .lineLimit(1)
                .truncationMode(.middle)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 12)
            if isRunning {
                IconButton(systemImage: "stop.circle", help: "Stop") { session.stop() }
                    .keyboardShortcut(".", modifiers: .command)
            }
            IconButton(systemImage: "arrow.clockwise", help: "Regenerate") { session.regenerate() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(session.phase == .gathering)
            IconButton(systemImage: "doc.on.doc", help: "Copy as Markdown") { RecapActions.copy(markdown()) }
                .disabled(!hasContent)
            IconButton(systemImage: "square.and.arrow.down", help: "Save as Markdown…") {
                RecapActions.save(markdown(), suggestedName: title, in: NSApp.keyWindow)
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(!hasContent)
        }
        .padding(.leading, 86)
        .padding(.trailing, 12)
        .frame(height: 52)
        .background(theme[ThemeKey.titleBarBackground])
        .windowTitleBarArea()
        .allowsWindowActivationEvents(true)
    }

    private var isRunning: Bool {
        session.summaryPhase == .running || session.summaryPhase == .estimating
    }

    private var hasContent: Bool {
        session.phase == .ready
    }

    /// What's on screen, as Markdown: the summary (with any More detail)
    /// or the log.
    private func markdown() -> String {
        guard let input = session.input else { return "" }
        let format = RecapFormat()
        let header = RecapMarkdown.Header(
            title: title,
            subtitle: RecapActions.subtitle(session.scope, input: input, speakers: session.findings.speakers.count, app: app, format: format),
            notes: RecapActions.notes(for: input, output: session.scope.output, format: format),
            conversationNames: RecapActions.conversationNames(input)
        )
        switch session.scope.output {
        case .log:
            return RecapMarkdown.log(header: header, input: input, format: format)
        case .summary:
            return RecapMarkdown.summary(
                header: header,
                findings: session.findings,
                summary: session.summary,
                details: session.details.compactMapValues(\.detail),
                format: format
            )
        }
    }
}

// MARK: - Scope bar

/// Who, Where and When, and Summary or Log. Changing any of them reads
/// the messages again (switching between Summary and Log doesn't).
private struct RecapScopeBar: View {
    @Environment(AppModel.self) private var app
    @Environment(IntelligenceServices.self) private var intelligence
    @Environment(\.theme) private var theme
    let session: RecapSession
    @Binding var choosesPerson: Bool

    /// The channel the Recap was first opened for, offered under Where.
    @State private var origin: BufferID?
    @State private var showsCustomSpan = false

    var body: some View {
        let scope = session.scope
        HStack(spacing: 4) {
            RecapPersonButton(session: session, isPresented: $choosesPerson, origin: origin)
            whereMenu(scope)
            whenMenu(scope)
            Spacer(minLength: 8)
            RecapOutputPicker(
                output: scope.output,
                summaryUnavailable: summaryUnavailableReason
            ) { output in
                var copy = session.scope
                copy.output = output
                session.update(copy)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(theme[ThemeKey.titleBarBackground].opacity(0.6))
        .onAppear {
            if origin == nil, case .buffer(let id) = scope.place { origin = id }
            if origin == nil { origin = app.selectedBufferID.flatMap { app.lookup($0)?.buffer.kind == .server ? nil : $0 } }
        }
    }

    private var summaryUnavailableReason: String? {
        let status = intelligence.availability.status
        return status.isAvailable ? nil : status.detail
    }

    // MARK: Where

    private func whereMenu(_ scope: RecapScope) -> some View {
        Menu {
            if let origin, let buffer = app.lookup(origin)?.buffer {
                choice(buffer.name, isOn: scope.place == .buffer(origin)) { set(place: .buffer(origin)) }
                Divider()
            }
            ForEach(app.sessions.filter { !$0.isBouncerControl }, id: \.id) { network in
                choice(network.displayName, isOn: scope.place == .network(network.id)) { set(place: .network(network.id)) }
            }
            if app.sessions.count > 1 {
                Divider()
                choice("All Networks", isOn: scope.place == .everywhere) { set(place: .everywhere) }
            }
        } label: {
            RecapScopeLabel(name: "Where", value: whereTitle(scope))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Where: \(whereTitle(scope))")
    }

    private func whereTitle(_ scope: RecapScope) -> String {
        switch scope.place {
        case .everywhere: "All networks"
        default: RecapActions.placeName(scope.place, app: app)
        }
    }

    private func set(place: RecapScope.Place) {
        var copy = session.scope
        copy.place = place
        session.update(copy)
    }

    // MARK: When

    private func whenMenu(_ scope: RecapScope) -> some View {
        Menu {
            choice(unreadTitle, isOn: scope.span == .sinceUnread) { set(span: .sinceUnread) }
            Divider()
            ForEach(RecapScope.Span.quickPicks, id: \.self) { span in
                choice(span.title, isOn: scope.span == span) { set(span: span) }
            }
            Divider()
            Button("Custom…") { showsCustomSpan = true }
        } label: {
            RecapScopeLabel(name: "When", value: scope.span.title)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("When: \(scope.span.title)")
        .popover(isPresented: $showsCustomSpan, arrowEdge: .bottom) {
            RecapSpanField(initial: scope.span) { span in
                showsCustomSpan = false
                set(span: span)
            }
            .padding(14)
        }
    }

    /// "Since your first unread (412)" while that's what it shows.
    private var unreadTitle: String {
        guard session.scope.span == .sinceUnread, let unread = session.input?.unreadLines, unread > 0 else {
            return "Since Your First Unread"
        }
        return "Since Your First Unread (\(RecapFormat.messages(unread)))"
    }

    private func set(span: RecapScope.Span) {
        var copy = session.scope
        copy.span = span
        session.update(copy)
    }

    private func choice(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Toggle(title, isOn: Binding(get: { isOn }, set: { _ in action() }))
    }
}

/// "Who  Anyone ⌄": a scope control's label.
struct RecapScopeLabel: View {
    @Environment(\.theme) private var theme
    let name: String
    let value: String

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 5) {
            Text(name)
                .foregroundStyle(theme[ThemeKey.titleBarSecondaryForeground])
            Text(value)
                .foregroundStyle(theme[ThemeKey.titleBarForeground])
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(theme[ThemeKey.titleBarSecondaryForeground])
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(hovering ? theme[ThemeKey.chatHoverBackground] : .clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

/// Summary or Log, as two halves of a capsule. Summary is off, saying why,
/// while Apple Intelligence can't run.
private struct RecapOutputPicker: View {
    @Environment(\.theme) private var theme
    let output: RecapScope.Output
    let summaryUnavailable: String?
    let choose: (RecapScope.Output) -> Void

    var body: some View {
        HStack(spacing: 2) {
            segment(.summary, "Summary", systemImage: "apple.intelligence")
                .disabled(summaryUnavailable != nil)
                .help(summaryUnavailable ?? "Apple Intelligence's report")
            segment(.log, "Log", systemImage: "text.alignleft")
                .help("Every message, as written")
        }
        .padding(2)
        .background(Capsule().fill(theme[ThemeKey.chatHoverBackground]))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Output")
    }

    private func segment(_ value: RecapScope.Output, _ title: String, systemImage: String) -> some View {
        let isOn = output == value
        return Button { choose(value) } label: {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .foregroundStyle(theme[isOn ? ThemeKey.accentForeground : ThemeKey.titleBarForeground])
                .background(Capsule().fill(isOn ? theme[ThemeKey.accent] : .clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

// MARK: - Who

/// "Who  Anyone ⌄", opening a picker: anyone, or one person from the
/// members and recent speakers, or a nick typed in.
private struct RecapPersonButton: View {
    @Environment(AppModel.self) private var app
    let session: RecapSession
    @Binding var isPresented: Bool
    let origin: BufferID?

    var body: some View {
        Button { isPresented.toggle() } label: {
            RecapScopeLabel(name: "Who", value: session.scope.person ?? "Anyone")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Who: \(session.scope.person ?? "Anyone")")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            RecapPersonPicker(
                current: session.scope.person,
                people: RecapPeople.candidates(for: session.scope, origin: origin, speakers: session.findings.speakers.map(\.nick), app: app)
            ) { person in
                isPresented = false
                choose(person)
            }
        }
    }

    /// A person's Recap covers their private conversation too, so one
    /// chosen in a channel covers the network (narrow it back with Where).
    private func choose(_ person: String?) {
        var scope = session.scope
        scope.person = person
        if person != nil, case .buffer(let id) = scope.place {
            scope.place = .network(id.networkID)
        }
        session.update(RecapScope(place: scope.place, person: scope.person, span: scope.span, output: scope.output))
    }
}

/// Who to suggest for a person's Recap.
@MainActor
enum RecapPeople {
    /// Recent speakers first (in the Recap and where it was opened), then
    /// the members of its channel; never you.
    static func candidates(for scope: RecapScope, origin: BufferID?, speakers: [String], app: AppModel) -> [String] {
        var seen = Set<String>()
        var people: [String] = []
        func add(_ nick: String, own: String) {
            let key = nick.lowercased()
            guard !nick.isEmpty, key != own.lowercased(), seen.insert(key).inserted else { return }
            people.append(nick)
        }
        for speaker in speakers { add(speaker, own: "") }
        var buffers: [(NetworkSession, BufferModel)] = []
        if let origin, let target = app.lookup(origin) { buffers.append(target) }
        switch scope.place {
        case .buffer(let id): if id != origin, let target = app.lookup(id) { buffers.append(target) }
        case .network(let id):
            if let session = app.session(for: id) { buffers += session.buffers.map { (session, $0) } }
        case .everywhere:
            buffers += app.sessions.flatMap { session in session.buffers.map { (session, $0) } }
        }
        for (session, buffer) in buffers.prefix(40) {
            for line in buffer.lines.suffix(300).reversed() where line.kind.isConversation && !line.isSelf {
                add(line.nick ?? "", own: session.nick)
            }
            if buffer.kind == .query { add(buffer.name, own: session.nick) }
        }
        if let origin, let (session, buffer) = app.lookup(origin), buffer.kind == .channel {
            for member in buffer.members.prefix(500) { add(member.nick, own: session.nick) }
        }
        return people
    }
}

private struct RecapPersonPicker: View {
    @Environment(\.theme) private var theme
    let current: String?
    let people: [String]
    let choose: (String?) -> Void

    @State private var query = ""

    var body: some View {
        let matches = filtered
        VStack(alignment: .leading, spacing: 8) {
            Text("Recap conversations with")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
            ThemedTextField("Type a nick", text: $query, accessibilityName: "Nick") {
                let typed = query.trimmingCharacters(in: .whitespaces)
                if !typed.isEmpty { choose(matches.first { $0.caseInsensitiveCompare(typed) == .orderedSame } ?? typed) }
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if query.isEmpty { row("Anyone", isOn: current == nil) { choose(nil) } }
                    ForEach(matches, id: \.self) { nick in
                        row(nick, isOn: current?.caseInsensitiveCompare(nick) == .orderedSame) { choose(nick) }
                    }
                    if matches.isEmpty, !query.isEmpty {
                        row("Recap \(query.trimmingCharacters(in: .whitespaces))", isOn: false) {
                            choose(query.trimmingCharacters(in: .whitespaces))
                        }
                    }
                }
            }
            .frame(height: 220)
        }
        .frame(width: 240)
        .padding(12)
    }

    private var filtered: [String] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return Array(people.prefix(60)) }
        let starts = people.filter { $0.lowercased().hasPrefix(needle) }
        let contains = people.filter { !$0.lowercased().hasPrefix(needle) && $0.lowercased().contains(needle) }
        return Array((starts + contains).prefix(60))
    }

    private func row(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        RecapPickerRow(title: title, isOn: isOn, action: action)
    }
}

private struct RecapPickerRow: View {
    @Environment(\.theme) private var theme
    let title: String
    let isOn: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(theme[ThemeKey.settingsForeground])
                Spacer()
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme[ThemeKey.accent])
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 5).fill(hovering ? theme[ThemeKey.chatHoverBackground] : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

// MARK: - Span

/// A number and a unit: "Recap the last [12] [hours]".
struct RecapSpanField: View {
    @Environment(\.theme) private var theme
    let initial: RecapScope.Span
    let choose: (RecapScope.Span) -> Void

    @State private var count = 2
    @State private var unit = RecapScope.Span.Unit.hours

    var body: some View {
        HStack(spacing: 8) {
            Text("The last")
                .font(.system(size: 13))
                .foregroundStyle(theme[ThemeKey.settingsForeground])
            TextField("Number", value: $count, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 56)
                .multilineTextAlignment(.trailing)
                .onSubmit { choose(.last(max(1, count), unit)) }
                .accessibilityLabel("How many")
            Stepper("How many", value: $count, in: 1...999)
                .labelsHidden()
            Picker("Unit", selection: $unit) {
                Text("minutes").tag(RecapScope.Span.Unit.minutes)
                Text("hours").tag(RecapScope.Span.Unit.hours)
                Text("days").tag(RecapScope.Span.Unit.days)
            }
            .labelsHidden()
            .fixedSize()
            Button("Recap") { choose(.last(max(1, count), unit)) }
                .buttonStyle(ThemedButtonStyle(prominent: true))
                .keyboardShortcut(.defaultAction)
        }
        .onAppear {
            guard case .last(let minutes) = initial else { return }
            if minutes % 1_440 == 0 { count = minutes / 1_440; unit = .days }
            else if minutes % 60 == 0 { count = minutes / 60; unit = .hours }
            else { count = minutes; unit = .minutes }
        }
    }
}
