import Foundation
import LittleOrbitDomain

/// The Match step's rows: the names in the file and what each can be matched to.
extension CSVImportViewModel {
    public var accountMatches: [ImportMatchRow] {
        matchRows { if case .account = $0 { true } else { false } }
    }

    public var categoryMatches: [ImportMatchRow] {
        matchRows {
            switch $0 {
            case .category, .subcategory: true
            default: false
            }
        }
    }

    public var payeeMatches: [ImportMatchRow] {
        matchRows { if case .payee = $0 { true } else { false } }
    }

    private func matchRows(_ include: (ImportMatchKind) -> Bool) -> [ImportMatchRow] {
        (preview?.matches ?? []).filter { include($0.key.kind) }
            .map { match in
                ImportMatchRow(
                    id: match.key,
                    name: match.parentName.map { ImportExportText.categoryPath(parent: $0, name: match.name) }
                        ?? match.name,
                    choice: match.choice,
                    options: options(for: match.key.kind),
                )
            }
    }

    private func options(for kind: ImportMatchKind) -> [ImportMatchOption] {
        switch kind {
        case .account:
            return accountOptions
        case .category(let categoryKind):
            return ledger.categories.filter { $0.kind == categoryKind && $0.parentID == nil && !$0.isArchived }
                .sorted { $0.sortOrder < $1.sortOrder }
                .map { ImportMatchOption(id: $0.id, name: $0.name) }
        case .subcategory(let categoryKind, _):
            let parents = Dictionary(uniqueKeysWithValues: ledger.categories.map { ($0.id, $0.name) })
            return ledger.categories.filter { $0.kind == categoryKind && $0.parentID != nil && !$0.isArchived }
                .map { category in
                    let parent = category.parentID.flatMap { parents[$0] } ?? ""
                    return ImportMatchOption(
                        id: category.id,
                        name: ImportExportText.categoryPath(parent: parent, name: category.name),
                    )
                }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .payee:
            return ledger.payees.filter { !$0.isArchived }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                .map { ImportMatchOption(id: $0.id, name: $0.name) }
        }
    }
}
