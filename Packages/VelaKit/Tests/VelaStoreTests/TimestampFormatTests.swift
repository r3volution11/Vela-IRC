// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
import VelaFoundation
@testable import VelaStore

@Suite struct TimestampFormatTests {
    private let us = Locale(identifier: "en_US")
    private let gb = Locale(identifier: "en_GB")
    private let de = Locale(identifier: "de_DE")

    @Test func systemFollowsTheLocalesHourCycle() {
        #expect(TimestampFormat.pattern(clock: .system, seconds: false, locale: us) == "h:mm a")
        #expect(TimestampFormat.pattern(clock: .system, seconds: true, locale: us) == "h:mm:ss a")
        #expect(TimestampFormat.pattern(clock: .system, seconds: false, locale: gb) == "HH:mm")
        #expect(TimestampFormat.pattern(clock: .system, seconds: false, locale: de) == "HH:mm")
        #expect(TimestampFormat.pattern(clock: .system, seconds: true, locale: de) == "HH:mm:ss")
    }

    /// The Mac's 24-hour time switch reaches the locale as an hour-cycle
    /// preference, which a locale keyword stands in for here.
    @Test func systemHonorsAnHourCycleOverride() {
        let us24 = Locale(identifier: "en_US@hours=h23")
        let gb12 = Locale(identifier: "en_GB@hours=h12")
        #expect(TimestampFormat.pattern(clock: .system, seconds: false, locale: us24) == "HH:mm")
        #expect(TimestampFormat.pattern(clock: .system, seconds: true, locale: gb12) == "h:mm:ss a")
    }

    @Test func explicitClocksIgnoreTheLocale() {
        for locale in [us, gb, de] {
            #expect(TimestampFormat.pattern(clock: .twelveHour, seconds: false, locale: locale) == "h:mm a")
            #expect(TimestampFormat.pattern(clock: .twelveHour, seconds: true, locale: locale) == "h:mm:ss a")
            #expect(TimestampFormat.pattern(clock: .twentyFourHour, seconds: false, locale: locale) == "HH:mm")
            #expect(TimestampFormat.pattern(clock: .twentyFourHour, seconds: true, locale: locale) == "HH:mm:ss")
        }
    }

    @Test func customPatternWins() {
        #expect(TimestampFormat.pattern(clock: .twelveHour, seconds: true, custom: "HH.mm", locale: us) == "HH.mm")
        #expect(TimestampFormat.pattern(clock: .system, seconds: false, custom: "EEE HH:mm", locale: gb) == "EEE HH:mm")
    }

    @Test func blankCustomPatternIsIgnored() {
        #expect(TimestampFormat.pattern(clock: .twentyFourHour, seconds: false, custom: "", locale: us) == "HH:mm")
        #expect(TimestampFormat.pattern(clock: .twelveHour, seconds: false, custom: "  ", locale: gb) == "h:mm a")
    }

    @Test func formatterWritesFixedPatternsAsGiven() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 14, minute: 47, second: 9)))
        let us24 = Locale(identifier: "en_US@hours=h23")
        let gb12 = Locale(identifier: "en_GB@hours=h12")
        #expect(TimestampFormat.formatter(pattern: "h:mm a", locale: us24).string(from: date) == "2:47 PM")
        #expect(TimestampFormat.formatter(pattern: "HH:mm:ss", locale: gb12).string(from: date) == "14:47:09")
        #expect(TimestampFormat.formatter(pattern: TimestampFormat.pattern(clock: .system, seconds: false, locale: us), locale: us)
            .string(from: date) == "2:47 PM")
    }

    @Test func settingKeys() {
        #expect(SettingKey.chatClock.defaultValue == .system)
        #expect(SettingKey.chatTimestampSeconds.defaultValue == false)
        #expect(SettingKey.chatTimestampFormat.defaultValue == "")
        #expect(SettingKey.chatClock.value(from: .string("12h")) == .twelveHour)
        #expect(SettingKey.chatClock.value(from: .string("24h")) == .twentyFourHour)
        #expect(SettingKey.chatClock.value(from: .string("25h")) == .system)
        #expect(SettingKey.chatClock.jsonValue(for: .twentyFourHour) == .string("24h"))
    }
}
