// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Testing
@testable import VelaIRC

private func span(_ text: String, _ style: IRCTextStyle = .plain) -> IRCTextSpan {
    IRCTextSpan(text: text, style: style)
}

@Suite struct IRCFormattingTests {
    @Test func plainTextIsOneSpan() {
        #expect(IRCFormatting.parse("hello") == [span("hello")])
        #expect(IRCFormatting.parse("") == [])
    }

    @Test func toggles() {
        let spans = IRCFormatting.parse("a\u{02}b\u{1D}c\u{02}d\u{1F}\u{1E}\u{11}e\u{0F}f")
        #expect(spans == [
            span("a"),
            span("b", IRCTextStyle(bold: true)),
            span("c", IRCTextStyle(bold: true, italic: true)),
            span("d", IRCTextStyle(italic: true)),
            span("e", IRCTextStyle(italic: true, underline: true, strikethrough: true, monospace: true)),
            span("f"),
        ])
    }

    @Test func foregroundOnly() {
        #expect(IRCFormatting.parse("\u{03}4red\u{03} plain") == [
            span("red", IRCTextStyle(foreground: .palette(4))),
            span(" plain"),
        ])
    }

    @Test func foregroundAndBackground() {
        #expect(IRCFormatting.parse("\u{03}04,12x") == [
            span("x", IRCTextStyle(foreground: .palette(4), background: .palette(12))),
        ])
        // Two-digit max: the third digit is text.
        #expect(IRCFormatting.parse("\u{03}123") == [span("3", IRCTextStyle(foreground: .palette(12)))])
    }

    @Test func foregroundChangeKeepsBackground() {
        #expect(IRCFormatting.parse("\u{03}2,3a\u{03}5b") == [
            span("a", IRCTextStyle(foreground: .palette(2), background: .palette(3))),
            span("b", IRCTextStyle(foreground: .palette(5), background: .palette(3))),
        ])
    }

    @Test func literalCommas() {
        // Comma not followed by a digit stays in the text.
        #expect(IRCFormatting.parse("\u{03}4,hello") == [span(",hello", IRCTextStyle(foreground: .palette(4)))])
        // Bare \x03 followed by a comma: reset + literal comma.
        #expect(IRCFormatting.parse("\u{03}4a\u{03},5b") == [
            span("a", IRCTextStyle(foreground: .palette(4))),
            span(",5b"),
        ])
        #expect(IRCFormatting.parse("\u{03}4,") == [span(",", IRCTextStyle(foreground: .palette(4)))])
    }

    @Test func color99IsDefault() {
        #expect(IRCFormatting.parse("\u{03}99,99x") == [span("x")])
        #expect(IRCFormatting.parse("\u{03}4,99x") == [span("x", IRCTextStyle(foreground: .palette(4)))])
    }

    @Test func hexColors() {
        #expect(IRCFormatting.parse("\u{04}FF8800orange") == [span("orange", IRCTextStyle(foreground: .rgb(0xFF8800)))])
        #expect(IRCFormatting.parse("\u{04}ff8800,000080x") == [
            span("x", IRCTextStyle(foreground: .rgb(0xFF8800), background: .rgb(0x000080))),
        ])
        // Invalid hex: bare \x04 resets colors; text is literal.
        #expect(IRCFormatting.parse("\u{03}4a\u{04}GGGGGGb") == [
            span("a", IRCTextStyle(foreground: .palette(4))),
            span("GGGGGGb"),
        ])
        // Background must be six hex digits, otherwise the comma is text.
        #expect(IRCFormatting.parse("\u{04}112233,12x") == [span(",12x", IRCTextStyle(foreground: .rgb(0x112233)))])
    }

    @Test func reverseAndReset() {
        #expect(IRCFormatting.parse("\u{16}rev\u{16}norm") == [
            span("rev", IRCTextStyle(reverse: true)),
            span("norm"),
        ])
        #expect(IRCFormatting.parse("\u{02}\u{03}4,5\u{16}x\u{0F}y") == [
            span("x", IRCTextStyle(bold: true, reverse: true, foreground: .palette(4), background: .palette(5))),
            span("y"),
        ])
    }

    @Test func mergesAdjacentIdenticalStyles() {
        // Toggling on and off with no text between produces no empty span.
        #expect(IRCFormatting.parse("a\u{02}\u{02}b\u{03}\u{03}c") == [span("abc")])
        #expect(IRCFormatting.parse("\u{02}x\u{03}4\u{03}y") == [span("xy", IRCTextStyle(bold: true))])
    }

    @Test func digitsAfterColorWithCombiningKeycap() {
        // "1\u{20E3}" is a single grapheme; the parser must still see the digit.
        let spans = IRCFormatting.parse("\u{03}1\u{20E3}")
        #expect(spans == [span("\u{20E3}", IRCTextStyle(foreground: .palette(1)))])
    }

    @Test func stripRemovesEverything() {
        let text = "\u{02}bold\u{02} \u{03}04,12color\u{03} \u{04}FFFFFF,000000hex\u{0F} \u{1D}\u{1F}\u{1E}\u{11}\u{16}x"
        #expect(IRCFormatting.strip(text) == "bold color hex x")
        #expect(IRCFormatting.strip("\u{03}4,hello") == ",hello")
        #expect(IRCFormatting.strip("no codes") == "no codes")
        #expect(!IRCFormatting.containsFormatting("plain 😀"))
    }

    @Test func paletteRGB() {
        #expect(IRCColor.paletteRGB.count == 99)
        #expect(IRCColor.palette(0).defaultRGB == 0xFFFFFF)
        #expect(IRCColor.palette(52).defaultRGB == 0xFF0000)
        #expect(IRCColor.palette(98).defaultRGB == 0xFFFFFF)
        #expect(IRCColor.palette(99).defaultRGB == nil)
        #expect(IRCColor.rgb(0x123456).defaultRGB == 0x123456)
    }
}

@Suite struct CTCPTests {
    @Test func parsesAction() throws {
        let parsed = try #require(CTCP.parse("\u{01}ACTION waves hello\u{01}"))
        #expect(parsed.command == "ACTION")
        #expect(parsed.argument == "waves hello")
        #expect(CTCP.actionText("\u{01}ACTION waves\u{01}") == "waves")
        #expect(CTCP.actionText("\u{01}VERSION\u{01}") == nil)
    }

    @Test func parsesWithoutArgumentOrClosingDelimiter() throws {
        let version = try #require(CTCP.parse("\u{01}version\u{01}"))
        #expect(version.command == "VERSION")
        #expect(version.argument == nil)
        let unterminated = try #require(CTCP.parse("\u{01}PING 12345"))
        #expect(unterminated.command == "PING")
        #expect(unterminated.argument == "12345")
        let empty = try #require(CTCP.parse("\u{01}ACTION \u{01}"))
        #expect(empty.argument == "")
    }

    @Test func rejectsNonCTCP() {
        #expect(CTCP.parse("hello") == nil)
        #expect(CTCP.parse("\u{01}\u{01}") == nil)
        #expect(CTCP.parse("") == nil)
    }

    @Test func encodes() {
        #expect(CTCP.encode("ACTION", "waves") == "\u{01}ACTION waves\u{01}")
        #expect(CTCP.encode("version", nil) == "\u{01}VERSION\u{01}")
        let parsed = CTCP.parse(CTCP.encode("PING", "1 2 3"))
        #expect(parsed?.command == "PING")
        #expect(parsed?.argument == "1 2 3")
    }
}
