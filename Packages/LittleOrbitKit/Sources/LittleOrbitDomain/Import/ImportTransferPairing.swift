import Foundation

/// Pairs the two halves of a transfer that a file lists once under each account (#60), after the accounts are
/// matched, so a remap or a new account's currency decides the pairs (D330, D332, D333, D335).
///
/// Two halves can pair when they're opposite halves between the same two matched accounts, in the same
/// direction, and no more than 2 minutes apart, both ends included. A candidate is valid when it has the same
/// amount in one currency, or any amount between two currencies; closeness only orders valid candidates, and
/// the closest pairs first. Equally close valid candidates that would make the same transfer (the same
/// accounts and currencies, amounts and the outgoing half's date and time) pair in file order, so a half
/// pairs at most once (D38, TR1–TR4). If they'd make different transfers, the half and those candidates can't
/// import. Only after that pass, mirrored same-currency halves with different amounts that are both still
/// unpaired can't import either, so they never import as two transfers (D335). Any other half left unpaired,
/// including one whose only candidate paired elsewhere, imports as one transfer.
struct ImportTransferPairing {
    /// Up to 2 minutes apart, both ends included (D330.2, D332.1).
    static let window: TimeInterval = 120

    /// What happens to one row of the file.
    enum Outcome: Equatable {
        /// The row, now standing for both halves.
        case merged(ImportRow)
        /// The other half of a merged row: it adds no row of its own.
        case absorbed
        /// The row can't import, for this reason.
        case failed(ImportRowIssue)
    }

    /// The accounts the rows refer to and their currencies, as matching will resolve them.
    struct Accounts {
        var refs: [(source: ImportRef?, destination: ImportRef?)]
        var currency: (ImportRef) -> String
    }

    private struct Half {
        var index: Int
        var outgoing: Bool
        var date: Date
        var amount: Decimal
        /// The two accounts are in different currencies.
        var isCross: Bool
    }

    private struct Group: Hashable {
        var source: ImportRef
        var destination: ImportRef
    }

    private struct Candidate {
        var other: Int
        var distance: TimeInterval
        var isValid: Bool
    }

    /// A valid pair, closest first, then in file order.
    private struct Edge: Comparable {
        var distance: TimeInterval
        var first: Int
        var second: Int

        static func < (lhs: Edge, rhs: Edge) -> Bool {
            (lhs.distance, lhs.first, lhs.second) < (rhs.distance, rhs.first, rhs.second)
        }
    }

    private var halves: [Int: Half] = [:]
    private var candidates: [Int: [Candidate]] = [:]
    private var edges: [Edge] = []
    private var partner: [Int: Int] = [:]
    private var failures: [Int: ImportRowIssue] = [:]

    /// The outcome of each row that pairing changes, by its index in `rows`.
    static func outcomes(_ rows: [ImportRow], accounts: Accounts) -> [Int: Outcome] {
        var pairing = ImportTransferPairing()
        for members in groups(rows, accounts: accounts).values {
            pairing.addCandidates(members)
        }
        pairing.pairClosest()
        pairing.failUnmatchedAmounts()
        return pairing.outcomes(rows)
    }

    /// The halves that can pair, by the two accounts they move money between.
    private static func groups(_ rows: [ImportRow], accounts: Accounts) -> [Group: [Half]] {
        var groups: [Group: [Half]] = [:]
        for (index, row) in rows.enumerated() {
            guard let side = row.transferHalf, row.kind == .transfer, row.issues.isEmpty, let date = row.date,
                let amount = row.amount, let source = accounts.refs[index].source,
                let destination = accounts.refs[index].destination, source != destination
            else {
                continue
            }
            let half = Half(
                index: index,
                outgoing: side == .outgoing,
                date: date,
                amount: amount,
                isCross: accounts.currency(source) != accounts.currency(destination),
            )
            groups[Group(source: source, destination: destination), default: []].append(half)
        }
        return groups
    }

    /// Every outgoing and incoming half of one group up to 2 minutes apart, valid or not.
    private mutating func addCandidates(_ members: [Half]) {
        let incoming = members.filter { !$0.outgoing }.sorted { $0.date < $1.date }
        for half in members {
            halves[half.index] = half
        }
        for out in members where out.outgoing {
            for back in incoming[Self.firstInWindow(incoming, of: out)...] {
                let offset = back.date.timeIntervalSince(out.date)
                guard offset <= Self.window else {
                    break
                }
                let distance = abs(offset)
                let isValid = out.isCross || out.amount == back.amount
                candidates[out.index, default: []]
                    .append(Candidate(other: back.index, distance: distance, isValid: isValid))
                candidates[back.index, default: []]
                    .append(Candidate(other: out.index, distance: distance, isValid: isValid))
                if isValid {
                    edges.append(
                        Edge(
                            distance: distance,
                            first: min(out.index, back.index),
                            second: max(out.index, back.index),
                        )
                    )
                }
            }
        }
    }

    /// The first of the date-sorted incoming halves no more than 2 minutes before `out`.
    private static func firstInWindow(_ incoming: [Half], of out: Half) -> Int {
        var low = incoming.startIndex
        var high = incoming.endIndex
        while low < high {
            let middle = (low + high) / 2
            if out.date.timeIntervalSince(incoming[middle].date) > window {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low
    }

    private func isOpen(_ index: Int) -> Bool {
        partner[index] == nil && failures[index] == nil
    }

    /// The open valid candidates exactly `distance` away, and whether they'd make different transfers.
    private func ties(of index: Int, at distance: TimeInterval) -> (members: [Int], isAmbiguous: Bool) {
        let members = (candidates[index] ?? [])
            .filter { $0.isValid && $0.distance == distance && isOpen($0.other) }
            .map(\.other)
        let transfers = Set(members.compactMap { halves[$0] }.map(Transfer.init))
        return (members, transfers.count > 1)
    }

    /// Valid pairs, closest first; ties that would make different transfers can't import (D330.2, D332.3).
    private mutating func pairClosest() {
        for edge in edges.sorted() where isOpen(edge.first) && isOpen(edge.second) {
            let first = ties(of: edge.first, at: edge.distance)
            let second = ties(of: edge.second, at: edge.distance)
            guard !first.isAmbiguous && !second.isAmbiguous else {
                for (index, tie) in [(edge.first, first), (edge.second, second)] where tie.isAmbiguous {
                    for member in [index] + tie.members {
                        failures[member] = .ambiguousTransferHalf
                    }
                }
                continue
            }
            partner[edge.first] = edge.second
            partner[edge.second] = edge.first
        }
    }

    /// D335: after the valid pairs, the amounts reason only for mirrored same-currency halves with different
    /// amounts that are both still unpaired. A half whose candidate paired elsewhere stays a single transfer.
    private mutating func failUnmatchedAmounts() {
        let unmatched = candidates.compactMap { index, list -> Int? in
            guard isOpen(index) else {
                return nil
            }
            return list.contains { !$0.isValid && isOpen($0.other) } ? index : nil
        }
        for index in unmatched {
            failures[index] = .transferAmountsMismatch
        }
    }

    private func outcomes(_ rows: [ImportRow]) -> [Int: Outcome] {
        var outcomes = failures.mapValues { Outcome.failed($0) }
        for (first, second) in partner where first < second {
            guard let one = halves[first], let other = halves[second] else {
                continue
            }
            let (out, back) = one.outgoing ? (one, other) : (other, one)
            outcomes[first] = .merged(
                Self.merge(rows[out.index], rows[back.index], at: rows[first], isCross: out.isCross)
            )
            outcomes[second] = .absorbed
        }
        return outcomes
    }

    /// What a pair would become, for telling equally close candidates apart (D333): the accounts and
    /// currencies are the group's, so the amounts and the outgoing half's date and time. Notes and the
    /// incoming half's time don't count.
    private struct Transfer: Hashable {
        var outgoingDate: Date?
        var outgoingAmount: Decimal?
        var incomingAmount: Decimal?

        init(_ half: Half) {
            if half.outgoing {
                outgoingDate = half.date
                outgoingAmount = half.amount
            } else {
                incomingAmount = half.amount
            }
        }
    }

    /// One transfer from both halves (D330.1, D330.3): the outgoing half's date, time and amount, the
    /// incoming half's amount as the amount received between currencies, and both notes, the outgoing half's
    /// first. It keeps the row number and account names of the half that comes first in the file, so matching
    /// sees the names in file order; both halves refer to the same accounts.
    private static func merge(_ out: ImportRow, _ back: ImportRow, at first: ImportRow, isCross: Bool) -> ImportRow {
        var row = first
        let other = first.rowNumber == out.rowNumber ? back : out
        row.date = out.date
        row.amount = out.amount
        row.destinationAmount = isCross ? back.amount : nil
        row.mergedRowNumbers.append(other.rowNumber)
        row.transferHalf = nil
        let notes: String? =
            switch (out.note, back.note) {
            case (let outNote?, let backNote?): outNote == backNote ? outNote : outNote + "\n" + backNote
            case (let only?, nil), (nil, let only?): only
            case (nil, nil): nil
            }
        let shortened = notes.map(ImportText.shortenedNote)
        row.note = shortened?.text
        let wasShortened =
            shortened?.wasShortened == true || out.warnings.contains(.notesShortened)
            || back.warnings.contains(.notesShortened)
        row.warnings = wasShortened ? [.notesShortened] : []
        return row
    }
}
