import Foundation
import LittleOrbitDomain
import LittleOrbitTheme

/// A category's colour: one of the `category/*` hues (UI Designer's #24 handoff). It's stored as the hue's
/// hex in `TransactionCategory.colorHex`.
public enum CategoryHue: String, CaseIterable, Sendable {
    case red, orange, amber, yellow, lime, green, teal, cyan, blue, indigo, purple, pink, gray

    public var token: ColorToken {
        switch self {
        case .red: CategoryColor.red
        case .orange: CategoryColor.orange
        case .amber: CategoryColor.amber
        case .yellow: CategoryColor.yellow
        case .lime: CategoryColor.lime
        case .green: CategoryColor.green
        case .teal: CategoryColor.teal
        case .cyan: CategoryColor.cyan
        case .blue: CategoryColor.blue
        case .indigo: CategoryColor.indigo
        case .purple: CategoryColor.purple
        case .pink: CategoryColor.pink
        case .gray: CategoryColor.gray
        }
    }

    /// What's stored for this hue.
    public var hex: String {
        token.light.hexString
    }

    init?(hex: String?) {
        guard let hex, let color = RGBAColor(hex: hex),
            let hue = Self.allCases.first(where: { $0.token.light == color })
        else {
            return nil
        }
        self = hue
    }
}

/// The icon and colour a category shows, with the handoff's hues for the built-in categories, which are
/// seeded with no colour.
enum CategoryAppearance {
    static let fallbackSymbol = "tag.fill"

    static func symbol(of category: TransactionCategory) -> String {
        category.iconName ?? fallbackSymbol
    }

    static func hue(of category: TransactionCategory) -> CategoryHue {
        CategoryHue(hex: category.colorHex) ?? seedHues[category.id] ?? .gray
    }

    /// The symbols the editor offers: the built-in categories' symbols, then some common ones.
    static let symbols: [String] = [
        "fork.knife", "cart.fill", "cup.and.saucer.fill", "car.fill", "fuelpump.fill", "tram.fill", "house.fill",
        "bolt.fill", "wifi", "phone.fill", "cross.case.fill", "heart.fill", "bag.fill", "tshirt.fill",
        "popcorn.fill", "gamecontroller.fill", "person.fill", "pawprint.fill", "graduationcap.fill", "book.fill",
        "airplane", "doc.text.fill", "umbrella.fill", "creditcard.fill", "banknote.fill", "briefcase.fill",
        "percent", "gift.fill", "dumbbell.fill", "wrench.and.screwdriver.fill", "tag.fill",
        "ellipsis.circle.fill", "plus.circle.fill",
    ]

    /// The handoff's seed hues (UI Designer, #24 6289110898).
    private static let seedHues: [UUID: CategoryHue] = [
        DefaultCategoryID.food: .orange, DefaultCategoryID.groceries: .orange, DefaultCategoryID.transport: .blue,
        DefaultCategoryID.housing: .indigo, DefaultCategoryID.utilities: .yellow, DefaultCategoryID.health: .red,
        DefaultCategoryID.shopping: .pink, DefaultCategoryID.entertainment: .purple,
        DefaultCategoryID.personal: .teal, DefaultCategoryID.education: .amber, DefaultCategoryID.travel: .cyan,
        DefaultCategoryID.fees: .lime, DefaultCategoryID.insurance: .green, DefaultCategoryID.otherExpense: .gray,
        DefaultCategoryID.salary: .green, DefaultCategoryID.interest: .teal, DefaultCategoryID.gifts: .pink,
        DefaultCategoryID.otherIncome: .gray,
    ]
}
