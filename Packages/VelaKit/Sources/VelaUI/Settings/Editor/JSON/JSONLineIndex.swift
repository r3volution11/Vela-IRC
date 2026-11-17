// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Where each line of a text starts (UTF-16 offsets), kept up to date edit
/// by edit so the line-number gutter never rescans a large file.
///
/// Line breaks are `\n`, `\r\n` and `\r`, as in ``JSONCScanner``.
nonisolated struct JSONLineIndex: Equatable, Sendable {
    /// The offset each line starts at; the first is always 0.
    private(set) var starts: [Int] = [0]

    init() {}

    init(_ text: NSString) {
        starts = [0]
        appendStarts(in: text, from: 0, to: text.length)
    }

    init(_ text: String) {
        self.init(text as NSString)
    }

    var lineCount: Int { starts.count }

    /// The 0-based line containing `offset`.
    func line(containing offset: Int) -> Int {
        var low = 0, high = starts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if starts[mid] <= offset {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return low
    }

    /// Where 0-based `line` starts.
    func start(ofLine line: Int) -> Int {
        starts[max(0, min(line, starts.count - 1))]
    }

    /// Updates the index after an edit.
    ///
    /// - Parameters:
    ///   - editedRange: The changed characters, in the new text.
    ///   - delta: The change in length.
    ///   - text: The text after the edit.
    mutating func update(editedRange: NSRange, delta: Int, in text: NSString) {
        // One character of slack on each side catches `\r` and `\n` pairs
        // that the edit split or joined.
        let scanStart = max(0, editedRange.location - 1)
        let scanEnd = min(text.length, editedRange.location + editedRange.length + 1)
        let oldScanEnd = scanEnd - delta

        // Starts in (scanStart, oldScanEnd] came from line breaks the scan
        // covers again; later ones move by delta.
        let firstRemoved = firstIndex(after: scanStart)
        let firstKept = firstIndex(after: oldScanEnd)
        var updated = Array(starts[..<firstRemoved])
        updated.append(contentsOf: JSONLineIndex.breaks(in: text, from: scanStart, to: scanEnd))
        updated.append(contentsOf: starts[max(firstKept, firstRemoved)...].map { $0 + delta })
        starts = updated
    }

    /// Index of the first start greater than `offset`.
    private func firstIndex(after offset: Int) -> Int {
        var low = 0, high = starts.count
        while low < high {
            let mid = (low + high) / 2
            if starts[mid] <= offset {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }

    private mutating func appendStarts(in text: NSString, from start: Int, to end: Int) {
        starts.append(contentsOf: JSONLineIndex.breaks(in: text, from: start, to: end))
    }

    /// Line starts produced by the line breaks in `[start, end)`: the
    /// offset after each `\n`, and after each `\r` not followed by `\n`.
    private static func breaks(in text: NSString, from start: Int, to end: Int) -> [Int] {
        guard end > start else { return [] }
        let length = text.length
        var result: [Int] = []
        let chunk = 4096
        var buffer = [unichar](repeating: 0, count: chunk + 1)
        var position = start
        while position < end {
            // Read one extra character to see what follows a `\r`.
            let count = min(chunk, end - position)
            let readCount = min(count + 1, length - position)
            buffer.withUnsafeMutableBufferPointer { pointer in
                text.getCharacters(pointer.baseAddress!, range: NSRange(location: position, length: readCount))
            }
            for i in 0..<count {
                let c = buffer[i]
                if c == 0x0A {
                    result.append(position + i + 1)
                } else if c == 0x0D {
                    let followedByLF = i + 1 < readCount && buffer[i + 1] == 0x0A
                    if !followedByLF { result.append(position + i + 1) }
                }
            }
            position += count
        }
        return result
    }
}
