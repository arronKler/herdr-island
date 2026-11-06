import XCTest
@testable import IslandCore

final class TerminalTextTests: XCTestCase {
    func testBlankRowsSeparateBlocks() {
        let rows = TerminalText.lines(from: "one\n\ntwo\n\nthree")
        XCTAssertEqual(rows, ["one", "", "two", "", "three"])
    }

    func testCarriageReturnKeepsTheRedrawnRow() {
        XCTAssertEqual(
            TerminalText.lines(from: "progress 10%\rprogress 90%\ndone"),
            ["progress 90%", "done"]
        )
    }

    func testWindowsLineEndingsAndTrailingWhitespaceAreNormalized() {
        XCTAssertEqual(
            TerminalText.lines(from: "prompt ❯\u{00A0}\r\noutput   \r\n"),
            ["prompt ❯", "output"]
        )
    }

    func testKeepsOnlyTheNewestRows() {
        let rows = TerminalText.lines(from: (1...80).map(String.init).joined(separator: "\n"), limit: 60)
        XCTAssertEqual(rows.count, 60)
        XCTAssertEqual(rows.first, "21")
        XCTAssertEqual(rows.last, "80")
    }

    func testEmptyInputHasNoRows() {
        XCTAssertEqual(TerminalText.lines(from: ""), [])
        XCTAssertEqual(TerminalText.lines(from: "\n\n\n"), [])
        XCTAssertEqual(TerminalText.lines(from: "body", limit: 0), [])
    }

    func testTailNormalizationPreservesUnicodeAndBlankRowsAtLimit() {
        let raw = String(repeating: "old output\n", count: 1_000)
            + "旧\r新的 👩🏽‍💻\u{2003}\r\n\n下一行\u{00A0}\n\t\n\n"
        XCTAssertEqual(TerminalText.lines(from: raw, limit: 3), ["新的 👩🏽‍💻", "", "下一行"])
        XCTAssertEqual(TerminalText.lines(from: raw, limit: 2), ["", "下一行"])
        XCTAssertEqual(TerminalText.lines(from: raw, limit: 1), ["下一行"])
    }

    func testTailNormalizationMatchesReferenceForMixedCarriageReturns() {
        let chunks = ["", "a", "中👨‍👩‍👧‍👦", " \t", "\r", "a\rb", "a\r\r", "\rredraw\u{2003}"]
        for first in chunks {
            for last in chunks {
                let raw = first + "\n\n" + last + "\n"
                for limit in [1, 2, 60] {
                    var expected = raw.components(separatedBy: "\n").map { raw -> String in
                        var row = raw
                        if row.hasSuffix("\r") { row.removeLast() }
                        if let redraw = row.split(separator: "\r", omittingEmptySubsequences: false).last,
                           !redraw.isEmpty { row = String(redraw) }
                        while row.last?.isWhitespace == true { row.removeLast() }
                        return row
                    }
                    while expected.last == "" { expected.removeLast() }
                    XCTAssertEqual(TerminalText.lines(from: raw, limit: limit), Array(expected.suffix(limit)))
                }
            }
        }
    }

    func testStructuredRowsCoverBoxesGridsTablesAndRules() {
        XCTAssertTrue(TerminalText.isStructured("│ name │ status │"))
        XCTAssertTrue(TerminalText.isStructured("╭──────────╮"))
        XCTAssertTrue(TerminalText.isStructured("+--------+--------+"))
        XCTAssertTrue(TerminalText.isStructured("| name | status |"))
        XCTAssertTrue(TerminalText.isStructured("NAME       READY   STATUS    RESTARTS   AGE"))
        XCTAssertTrue(TerminalText.isStructured("────────────────────────────────"))
    }

    func testProseRowsWrap() {
        XCTAssertFalse(TerminalText.isStructured("plain prose that wraps inside the panel"))
        XCTAssertFalse(TerminalText.isStructured("    indented prose with one single gap"))
    }
}
