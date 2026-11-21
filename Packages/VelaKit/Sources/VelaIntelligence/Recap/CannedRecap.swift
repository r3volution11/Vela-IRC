// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Canned Recaps for demo mode, screenshots and tests; work on any Mac.
/// Each conversation's topics are Catch me up's canned ones (hand-written
/// for the demo channels), with hand-written overviews, decisions,
/// questions and follow-ups for the demo's channels, each shown only when
/// its message is among the lines read. Results stream in three steps.
extension CannedSummarizer: RecapSummarizer {
    public nonisolated func plan(_ input: RecapInput) async -> RecapPlan {
        // About a pass per 120 lines, as on a Mac with a 4,096-token model.
        let lines = min(input.lineCount, RecapLimits.summaryLines)
        let parts = max(1, Int((Double(lines) / 120).rounded(.up)))
        let passes = parts == 1 ? 1 : parts + 1
        return RecapPlan(passes: passes, transcriptTokens: lines * 25, estimatedSeconds: Double(passes) * 18)
    }

    public nonisolated func recap(_ input: RecapInput) -> AsyncThrowingStream<RecapSummary, Error> {
        let delay = stepDelay
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for step in try Self.recapSteps(for: input) {
                        if delay > .zero { try await Task.sleep(for: delay) }
                        continuation.yield(step)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public nonisolated func detail(_ request: RecapDetailRequest) -> AsyncThrowingStream<RecapDetail, Error> {
        let delay = stepDelay
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let points = Self.detailPoints(for: request)
                    guard !points.isEmpty else { throw CatchUpError.nothingToSummarize }
                    if delay > .zero { try await Task.sleep(for: delay) }
                    continuation.yield(RecapDetail(points: Array(points.prefix(2))))
                    if delay > .zero { try await Task.sleep(for: delay) }
                    continuation.yield(RecapDetail(points: points, isComplete: true))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Steps

    /// Reading, then the parts' topics, then the finished report.
    nonisolated static func recapSteps(for input: RecapInput) throws -> [RecapSummary] {
        let final = try recapSummary(for: input)
        var reading = RecapSummary(messageCount: final.messageCount)
        reading.progress = RecapProgress(messagesRead: final.messageCount / 3, messagesTotal: final.messageCount, secondsLeft: 20)
        var parts = final
        parts.overview = []
        parts.isComplete = false
        parts.topicsAreProvisional = true
        parts.progress = RecapProgress(messagesRead: final.messageCount, messagesTotal: final.messageCount, isWriting: true, secondsLeft: 6)
        return [reading, parts, final]
    }

    /// The finished canned report for `input`.
    nonisolated static func recapSummary(for input: RecapInput) throws -> RecapSummary {
        let transcript = RecapTranscript(input)
        guard !transcript.isEmpty else { throw CatchUpError.nothingToSummarize }
        var overview: [String] = []
        var topics: [RecapTopic] = []
        var notes: [RecapNote] = []
        var notesForYou: [UUID: String] = [:]
        for conversation in input.conversations {
            let lines = conversation.lines
            func line(containing anchor: String) -> RecapLine? {
                lines.first { $0.text.localizedCaseInsensitiveContains(anchor) }
            }
            func reference(_ line: RecapLine) -> RecapReference {
                RecapReference(conversation: conversation.id, lineID: line.id, time: line.time)
            }
            let script = DemoRecapScript.scripts[conversation.name.lowercased()]
            if let script {
                overview += script.overview.filter { line(containing: $0.anchor) != nil }.map(\.text)
                for note in script.notes {
                    guard let found = line(containing: note.anchor) else { continue }
                    notes.append(RecapNote(
                        id: "\(note.kind.rawValue)-\(found.id.uuidString)", kind: note.kind, text: note.text,
                        owner: note.owner, reference: reference(found)
                    ))
                }
                for you in script.forYou {
                    if let found = line(containing: you.anchor) { notesForYou[found.id] = you.text }
                }
            }
            // Catch me up's canned topics for the same lines.
            let request = CatchUpRequest(
                bufferID: conversation.id, bufferName: conversation.name, networkName: conversation.networkName,
                ownNick: conversation.ownNick,
                lines: lines.map { CatchUpLine(id: $0.id, time: $0.time, nick: $0.nick, text: $0.text, isAction: $0.isAction) }
            )
            guard let catchUp = try? summary(for: request) else { continue }
            if script == nil, !catchUp.overview.isEmpty { overview.append(catchUp.overview) }
            let starts = catchUp.topics.compactMap(\.firstLineID)
            for topic in catchUp.topics {
                guard let first = topic.firstLineID, let startIndex = lines.firstIndex(where: { $0.id == first }) else { continue }
                // Up to where the next topic here starts.
                let nextStart = lines.indices.first { $0 > startIndex && starts.contains(lines[$0].id) } ?? lines.endIndex
                topics.append(RecapTopic(
                    id: "topic-\(topics.count)",
                    title: topic.title,
                    summary: topic.summary,
                    participants: topic.participants,
                    start: reference(lines[startIndex]),
                    lineIDs: lines[startIndex..<nextStart].map(\.id)
                ))
            }
        }
        topics.sort { ($0.start?.time ?? .distantFuture) < ($1.start?.time ?? .distantFuture) }
        topics = topics.prefix(RecapPrompts.maximumTopics).enumerated().map { index, topic in
            var copy = topic
            copy.id = "topic-\(index)"
            return copy
        }
        notes.sort { ($0.reference?.time ?? .distantFuture) < ($1.reference?.time ?? .distantFuture) }
        return RecapSummary(
            overview: Array(overview.prefix(RecapPrompts.maximumOverview)),
            topics: topics,
            notes: notes,
            notesForYou: notesForYou,
            messageCount: transcript.entries.count,
            isComplete: true
        )
    }

    /// Points quoting the first few messages behind a topic or note.
    nonisolated static func detailPoints(for request: RecapDetailRequest) -> [String] {
        let speakers = request.lines.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        return speakers.prefix(4).map { line in
            let text = CatchUpTranscript.clean(line.text, maximumLength: 110)
            return line.isAction ? "\(line.nick) \(text)" : "\(line.nick) said “\(text)”"
        }
    }
}

/// Hand-written parts of the demo channels' Recaps. Each is shown only
/// when a line containing its anchor is among the lines read.
nonisolated private struct DemoRecapScript {
    struct Sentence {
        let anchor: String
        let text: String
    }

    struct Note {
        let anchor: String
        let kind: RecapNote.Kind
        let text: String
        var owner: String?
    }

    var overview: [Sentence] = []
    var notes: [Note] = []
    var forYou: [Sentence] = []

    static let scripts: [String: DemoRecapScript] = [
        "#vela": DemoRecapScript(
            overview: [
                Sentence(anchor: "theme engine landed", text: "kenji landed the token-based theme engine, and Palenight with the grouped layout is a hit."),
                Sentence(anchor: "doug: can you review", text: "wren is waiting on your review of the sidebar rail PR."),
                Sentence(anchor: "Crab Nebula", text: "theo's Crab Nebula photo is the reference for the Ocean theme."),
            ],
            notes: [
                Note(anchor: "that's the vibe for the Ocean theme", kind: .decision, text: "The Crab Nebula photo sets the look for the Ocean theme."),
                Note(anchor: "chathistory + reactions", kind: .question, text: "Which IRCv3 specs come first? lukas wants chathistory and reactions."),
                Note(anchor: "on it", kind: .followUp, text: "Review wren's sidebar rail PR.", owner: "doug"),
            ],
            forYou: [
                Sentence(anchor: "doug: can you review", text: "wren asked you to review the sidebar rail PR."),
            ]
        ),
        "#media": DemoRecapScript(
            overview: [
                Sentence(anchor: "preview sizes are split up", text: "Links, videos and images now each have their own preview size, and Standard is the new default link card."),
            ],
            notes: [
                Note(anchor: "preview sizes are split up", kind: .decision, text: "Links, videos and images each get their own preview size."),
                Note(anchor: "link cards come in", kind: .decision, text: "Standard is the default link card size."),
            ]
        ),
        "#macdev": DemoRecapScript(
            overview: [
                Sentence(anchor: "Liquid Glass sidebar", text: "irene is replacing the Liquid Glass sidebar with a custom split view."),
            ],
            notes: [
                Note(anchor: "the rewrite ships tonight", kind: .followUp, text: "Ship the custom split view rewrite tonight.", owner: "irene"),
            ]
        ),
        "#swift": DemoRecapScript(
            overview: [
                Sentence(anchor: "struct nonisolated", text: "felix learned that nonisolated struct opts a struct out of MainActor."),
            ],
            notes: [
                Note(anchor: "works since 6.2", kind: .decision, text: "Use nonisolated struct to keep a struct off MainActor (Swift 6.2 and later)."),
            ]
        ),
        "marisol": DemoRecapScript(
            overview: [
                Sentence(anchor: "theme credits doc", text: "marisol asked you to look at the theme credits doc, and you said notes are coming."),
            ],
            notes: [
                Note(anchor: "sending notes in a bit", kind: .followUp, text: "Send marisol notes on the theme credits doc.", owner: "doug"),
            ],
            forYou: [
                Sentence(anchor: "theme credits doc", text: "marisol asked you to look at the theme credits doc."),
            ]
        ),
        "#debian": DemoRecapScript(
            notes: [
                Note(anchor: "any issues with the new kernel", kind: .question, text: "Any issues with the new kernel on trixie?"),
            ]
        ),
    ]
}
