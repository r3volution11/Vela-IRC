// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
import VelaFoundation
@testable import VelaStore

@Suite("Dock settings")
struct DockSettingsTests {
    @Test func defaults() {
        #expect(SettingKey.dockShowBadge.defaultValue == true)
        #expect(SettingKey.dockBadgeCounts.defaultValue == [.mentions, .privateMessages])
        #expect(SettingKey.dockBadgeStyle.defaultValue == .capped)
        #expect(SettingKey.dockShowOffline.defaultValue == true)
        #expect(SettingKey.dockBounce.defaultValue == .off)
        #expect(SettingKey.dockBounceFor.defaultValue == [.mentions, .privateMessages])
        #expect(SettingKey.dockBadgeCounts.defaultJSONValue == .array(["mentions", "privateMessages"]))
    }

    @Test func rawValues() {
        #expect(DockBadgeCount.allCases.map(\.rawValue) == ["mentions", "privateMessages", "channels"])
        #expect(DockBadgeStyle.allCases.map(\.rawValue) == ["capped", "exact", "dot"])
        #expect(DockBounceStyle.allCases.map(\.rawValue) == ["off", "once", "untilActive"])
        #expect(DockBounceTrigger.allCases.map(\.rawValue) == ["mentions", "privateMessages"])
    }

    @Test func decodesListsAndDropsUnknownValues() {
        let counts = SettingKey.dockBadgeCounts
        #expect(counts.value(from: .array(["channels"])) == [.channels])
        #expect(counts.value(from: .array(["mentions", "channels", "privateMessages"])) == [.mentions, .channels, .privateMessages])
        #expect(counts.value(from: .array(["mentions", "bogus", 3])) == [.mentions], "unknown entries are dropped")
        #expect(counts.value(from: .array([])) == [], "an empty list counts nothing")
        #expect(counts.value(from: .string("mentions")) == [.mentions, .privateMessages], "not a list: the default")
        #expect(counts.value(from: nil) == [.mentions, .privateMessages])
        #expect(SettingKey.dockBounceFor.value(from: .array(["privateMessages", "channels"])) == [.privateMessages])
    }

    @Test func decodesChoicesAndFallsBackOnBadValues() {
        #expect(SettingKey.dockBadgeStyle.value(from: .string("dot")) == .dot)
        #expect(SettingKey.dockBadgeStyle.value(from: .string("exact")) == .exact)
        #expect(SettingKey.dockBadgeStyle.value(from: .string("Dot")) == .capped)
        #expect(SettingKey.dockBadgeStyle.value(from: .number(1)) == .capped)
        #expect(SettingKey.dockBounce.value(from: .string("untilActive")) == .untilActive)
        #expect(SettingKey.dockBounce.value(from: .string("always")) == .off)
        #expect(SettingKey.dockShowOffline.value(from: .bool(false)) == false)
        #expect(SettingKey.dockShowBadge.value(from: .string("no")) == true)
    }

    @Test func documentedUnderNotifications() throws {
        let keys = ["dock.showBadge", "dock.badgeCounts", "dock.badgeStyle", "dock.showOffline", "dock.bounce", "dock.bounceFor"]
        for key in keys {
            let descriptor = try #require(SettingsCatalog.descriptor(forKey: key), "\(key) isn't in the catalog")
            #expect(descriptor.settingsCategory == .notifications, "\(key)")
            #expect(!descriptor.summary.isEmpty)
        }
        #expect(SettingsCategory.category(forKey: "dock.bounce")?.paneID == "notifications")
        #expect(SettingsCatalog.descriptor(forKey: "dock.showBadge")?.title == "Dock: Show Badge")
        #expect(SettingsCatalog.descriptor(forKey: "dock.badgeCounts")?.title == "Dock: Badge Counts")
        #expect(SettingsCatalog.descriptor(forKey: "dock.showOffline")?.title == "Dock: Show Offline Mark")
        #expect(SettingsCatalog.descriptor(forKey: "dock.bounceFor")?.title == "Dock: Bounce For")
    }

    @Test func listsOfChoicesExposeTheirValues() throws {
        let counts = try #require(SettingsCatalog.descriptor(forKey: "dock.badgeCounts"))
        #expect(counts.enumValues == nil, "a list, not a single choice")
        #expect(counts.itemEnumValues == ["mentions", "privateMessages", "channels"])
        #expect(counts.schema["items"]?["enum"] == .array(["mentions", "privateMessages", "channels"]))
        #expect(SettingsCatalog.descriptor(forKey: "dock.bounceFor")?.itemEnumValues == ["mentions", "privateMessages"])
        #expect(SettingsCatalog.descriptor(forKey: "highlight.words")?.itemEnumValues == nil)
        #expect(SettingsCatalog.descriptor(forKey: "dock.badgeStyle")?.itemEnumValues == nil)
    }

    @Test func readableLabels() throws {
        let label = SettingsMetadata.enumLabel
        #expect(DockBadgeCount.allCases.map { label($0.rawValue) } == ["Mentions and highlight words", "Private messages", "All channel messages"])
        #expect(DockBadgeStyle.allCases.map { label($0.rawValue) } == ["Up to 99+", "Exact number", "Dot (•)"])
        #expect(DockBounceStyle.allCases.map { label($0.rawValue) } == ["Off", "Once", "Until you switch to Vela"])
    }

    @Test func validatorChecksEachListEntry() {
        let text = #"{ "dock.badgeCounts": ["mentions", "everything"], "dock.badgeStyle": "huge", "dock.bounceFor": "mentions" }"#
        let diagnostics = SettingsValidator.diagnostics(for: text)
        let notAllowed = diagnostics.filter { $0.kind == .valueNotAllowed }
        #expect(notAllowed.map(\.key) == ["dock.badgeCounts", "dock.badgeStyle"])
        #expect(notAllowed.first?.message.contains("“channels”") == true)
        #expect(diagnostics.contains { $0.kind == .typeMismatch && $0.key == "dock.bounceFor" })
        let fine = #"{ "dock.badgeCounts": ["channels", "privateMessages"], "dock.bounce": "untilActive" }"#
        #expect(SettingsValidator.diagnostics(for: fine).isEmpty)
    }

    @Test func completionOffersListEntries() throws {
        let marked = #"{"dock.badgeCounts": ["mentions", |]}"#
        let location = (marked as NSString).range(of: "|").location
        let text = (marked as NSString).replacingCharacters(in: NSRange(location: location, length: 1), with: "")
        guard case .value(let position) = SettingsCompletion.context(in: text, at: location) else {
            Issue.record("Expected a value context")
            return
        }
        #expect(position.isArrayElement)
        let items = SettingsCompletion.items(for: .value(position))
        #expect(items.map(\.label) == [#""mentions""#, #""privateMessages""#, #""channels""#])
        #expect(items.map(\.title) == ["Mentions and highlight words", "Private messages", "All channel messages"])
        #expect(items.allSatisfy { !$0.isDefault })
    }

    @Test func defaultSettingsDocumentListsThem() {
        let document = SettingsCatalog.defaultSettingsDocument()
        #expect(document.contains(#""dock.badgeCounts": ["mentions","privateMessages"]"#))
        #expect(document.contains(#""dock.bounce": "off""#))
        #expect(document.contains("    // dock\n"))
    }

    @MainActor
    @Test func readsAndWritesThroughTheStore() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let store = SettingsStore(fileURL: directory.file("settings.json"), watchForChanges: false)
        #expect(store[.dockBadgeCounts] == [.mentions, .privateMessages])
        store[.dockBadgeCounts] = [.channels]
        #expect(store.value(forKey: "dock.badgeCounts") == .array(["channels"]))
        store.setValue(.array(["privateMessages", "mentions"]), forKey: "dock.badgeCounts")
        #expect(store[.dockBadgeCounts] == [.privateMessages, .mentions])
        store[.dockBadgeStyle] = .dot
        #expect(store.value(forKey: "dock.badgeStyle") == .string("dot"))
        store.reset(.dockBadgeCounts)
        #expect(store[.dockBadgeCounts] == [.mentions, .privateMessages])
    }
}
