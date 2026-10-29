import Foundation

/// A part of a search the app ignored because its value is malformed (#28, PM answer 3). The rest of the search
/// still runs. The screens turn it into a hint such as “Use YYYY-MM-DD”.
public enum TransactionSearchIssue: Equatable, Sendable {
    /// `after:` or `before:` with a value that isn't a real `YYYY-MM-DD` day.
    case invalidDate(String)
    /// `year:` with a value that isn't four digits.
    case invalidYear(String)
    /// `type:` with a value other than expense, income or transfer.
    case invalidType(String)
}

/// What the user typed in the search field, read into plain words and operators (#28 AC 1 and 2).
///
/// - Words are separate terms, and every term has to match. A quoted phrase is one term.
/// - Known operators are `category:`, `payee:`, `tag:`, `notes:`, `after:`, `before:`, `year:` and `type:`. Their
///   names ignore case, and a value can be quoted: `payee:"Corner Bakery"`. Every operator has to match.
/// - An unknown operator such as `foo:bar` is plain text.
/// - A malformed value for a known operator is dropped and reported in `issues`. An operator with no value yet,
///   such as `payee:` while it's being typed, is dropped silently.
/// - An unclosed quote runs to the end of the text.
public struct TransactionSearchQuery: Equatable, Sendable {
    public var terms: [String] = []
    public var categories: [String] = []
    public var payees: [String] = []
    public var tags: [String] = []
    public var notes: [String] = []
    /// Inclusive (D21): the transaction's own day is on or after this one.
    public var after: CalendarDay?
    /// Inclusive (D21): the transaction's own day is on or before this one.
    public var before: CalendarDay?
    public var years: [Int] = []
    public var types: [TransactionType] = []
    public var issues: [TransactionSearchIssue] = []

    public init() {}

    /// Whether the query has nothing to match on, so it lists every transaction.
    public var isEmpty: Bool {
        terms.isEmpty && categories.isEmpty && payees.isEmpty && tags.isEmpty && notes.isEmpty && after == nil
            && before == nil && years.isEmpty && types.isEmpty
    }

    public static func parse(_ text: String) -> TransactionSearchQuery {
        var query = TransactionSearchQuery()
        for token in tokens(in: text) {
            query.add(token)
        }
        return query
    }

    // MARK: - Reading

    private enum Operator: String {
        case category, payee, tag, notes, after, before, year, type
    }

    private enum Token {
        case term(String)
        case filter(Operator, String)
    }

    private mutating func add(_ token: Token) {
        switch token {
        case .term(let text):
            terms.append(text)
        case .filter(let name, let value):
            guard !value.isEmpty else {
                return
            }
            add(name, value)
        }
    }

    private mutating func add(_ name: Operator, _ value: String) {
        switch name {
        case .category: categories.append(value)
        case .payee: payees.append(value)
        case .tag: tags.append(value)
        case .notes: notes.append(value)
        case .after, .before: addDate(value, isAfter: name == .after)
        case .year: addYear(value)
        case .type: addType(value)
        }
    }

    private mutating func addDate(_ value: String, isAfter: Bool) {
        guard let day = Self.day(value) else {
            issues.append(.invalidDate(value))
            return
        }
        if isAfter {
            after = max(after ?? day, day)
        } else {
            before = min(before ?? day, day)
        }
    }

    private mutating func addYear(_ value: String) {
        guard value.count == 4, value.allSatisfy(\.isASCIIDigit), let year = Int(value) else {
            issues.append(.invalidYear(value))
            return
        }
        years.append(year)
    }

    private mutating func addType(_ value: String) {
        guard let type = TransactionType(rawValue: value.lowercased()) else {
            issues.append(.invalidType(value))
            return
        }
        types.append(type)
    }

    /// Splits the text into terms and operators. Each step consumes at least one character, so it always ends.
    private static func tokens(in text: String) -> [Token] {
        var tokens: [Token] = []
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if character.isWhitespace {
                index = text.index(after: index)
                continue
            }
            if character == "\"" {
                let (phrase, next) = quoted(in: text, from: text.index(after: index))
                if !phrase.isEmpty {
                    tokens.append(.term(phrase))
                }
                index = next
                continue
            }
            var end = index
            while end < text.endIndex, !text[end].isWhitespace, text[end] != "\"" {
                end = text.index(after: end)
            }
            let word = String(text[index..<end])
            index = end
            guard let colon = word.firstIndex(of: ":"),
                let name = Operator(rawValue: word[..<colon].lowercased())
            else {
                tokens.append(.term(word))
                continue
            }
            var value = String(word[word.index(after: colon)...])
            if value.isEmpty, index < text.endIndex, text[index] == "\"" {
                let (phrase, next) = quoted(in: text, from: text.index(after: index))
                value = phrase
                index = next
            }
            tokens.append(.filter(name, value))
        }
        return tokens
    }

    /// The text up to the closing quote, or to the end when it's unclosed, and the index after it.
    private static func quoted(in text: String, from start: String.Index) -> (String, String.Index) {
        guard let close = text[start...].firstIndex(of: "\"") else {
            return (trimmed(text[start...]), text.endIndex)
        }
        return (trimmed(text[start..<close]), text.index(after: close))
    }

    private static func trimmed(_ text: Substring) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A real calendar day written exactly as `YYYY-MM-DD`.
    private static func day(_ text: String) -> CalendarDay? {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
            parts.allSatisfy({ $0.allSatisfy(\.isASCIIDigit) }),
            let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else {
            return nil
        }
        let candidate = CalendarDay(year: year, month: month, day: day)
        // Round-trips through the calendar, so 2026-13-45 and 2026-02-30 are refused rather than rolled over.
        guard let noon = TransactionCalendar.noon(on: candidate, timeZoneID: "UTC"),
            TransactionCalendar.calendarDay(of: noon, timeZoneID: "UTC") == candidate
        else {
            return nil
        }
        return candidate
    }
}
