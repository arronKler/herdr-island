import Foundation

/// The terminal rows Herdr hands back are a column-oriented snapshot, not prose.
/// The preview keeps their blank rows and carriage-return overwrites so blocks
/// stay separated, then keeps only the newest rows that fit the panel.
public enum TerminalText {
    public static let previewLineLimit = 60

    public static func lines(from raw: String, limit: Int = previewLineLimit) -> [String] {
        guard limit > 0 else { return [] }
        // Walk backward over UTF-8: newline is a single byte and cannot occur
        // inside another scalar. Only normalize rows that can reach the panel.
        var text = raw
        return text.withUTF8 { bytes in
            var end = bytes.count
            var rows: [String] = []
            rows.reserveCapacity(min(limit, previewLineLimit))
            while rows.count < limit {
                var start = end
                var hasCarriageReturn = false
                while start > 0, bytes[start - 1] != 10 {
                    start -= 1
                    hasCarriageReturn = hasCarriageReturn || bytes[start] == 13
                }
                let rawRow = String(decoding: bytes[start..<end], as: UTF8.self)
                let row: String
                if hasCarriageReturn {
                    row = visibleRow(rawRow)
                } else if start == end || (bytes[end - 1] > 32 && bytes[end - 1] < 127) {
                    // Most terminal rows end in ASCII text. They already have
                    // the desired representation, so skip Unicode row parsing.
                    row = rawRow
                } else {
                    row = trimmingTrailingWhitespace(rawRow)
                }
                if !rows.isEmpty || !row.isEmpty { rows.append(row) }
                guard start > 0 else { break }
                end = start - 1
            }
            return rows.reversed()
        }
    }

    /// Tables, diffs, and rules are laid out in terminal columns. Wrapping them
    /// turns the columns into unrelated rows, so the view keeps their width and
    /// pans horizontally instead.
    public static func isStructured(_ row: String) -> Bool {
        if row.contains(where: boxCharacters.contains) { return true }
        let rule = row.drop(while: { $0 == " " }).prefix(40)
        if rule.filter({ $0 == "─" || $0 == "━" || $0 == "═" }).count >= 8 { return true }
        let trimmed = row.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("+") && trimmed.contains("--") { return true }
        if trimmed.hasPrefix("|") && trimmed.filter({ $0 == "|" }).count >= 3 { return true }
        return internalColumnGaps(row) >= 2
    }

    /// Space-aligned output from tools such as kubectl and docker ps separates
    /// three or more columns with runs of two spaces and no drawing characters.
    private static func internalColumnGaps(_ row: String) -> Int {
        var gaps = 0
        var spaces = 0
        var sawContent = false
        for character in row {
            if character == " " {
                spaces += 1
            } else {
                if sawContent && spaces >= 2 { gaps += 1 }
                spaces = 0
                sawContent = true
            }
        }
        return gaps
    }

    private static let boxCharacters: Set<Character> = [
        "│", "┃", "║", "╭", "╮", "╰", "╯", "┌", "┐", "└", "┘",
        "├", "┤", "┬", "┴", "┼", "╔", "╗", "╚", "╝", "╠", "╣", "╦", "╩", "╬",
    ]

    private static func visibleRow(_ raw: String) -> String {
        var row = raw
        if row.hasSuffix("\r") { row.removeLast() }
        // A carriage return without a newline redraws the row in place.
        if row.utf8.contains(13),
           let redrawn = row.split(separator: "\r", omittingEmptySubsequences: false).last,
           !redrawn.isEmpty {
            row = String(redrawn)
        }
        return trimmingTrailingWhitespace(row)
    }

    private static func trimmingTrailingWhitespace(_ row: String) -> String {
        var end = row.endIndex
        while end > row.startIndex {
            let previous = row.index(before: end)
            guard row[previous].isWhitespace else { break }
            end = previous
        }
        return String(row[..<end])
    }
}
