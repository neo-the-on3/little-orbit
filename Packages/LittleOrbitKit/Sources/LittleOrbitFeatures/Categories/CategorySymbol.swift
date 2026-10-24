import Foundation

/// One of the editor's icons and the name it shows and VoiceOver reads, never made from the symbol string.
public struct CategorySymbol: Hashable, Sendable, Identifiable {
    public let symbol: String
    public let name: String

    init(symbol: String) {
        self.symbol = symbol
        name = CategorySymbolText.name(symbol) ?? CategorySymbolText.currentIcon
    }

    public var id: String {
        symbol
    }
}

/// The editor's icon names (UI Designer's #155 review), apart from `CategoryText` to keep each file short.
enum CategorySymbolText {
    // The name the editor shows and VoiceOver reads for one of its icons, each its own `category.symbol.*`
    // catalog key, so “More” never shares an entry with the toolbar’s “More”. `nil` for a symbol the editor
    // doesn’t list. Names never come from the symbol string.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    static func name(_ symbol: String) -> String? {
        switch symbol {
        case "fork.knife":
            FeatureText.string(
                key: "category.symbol.forkAndKnife",
                defaultValue: "Fork and Knife",
                comment: "Category icon name, shown in the editor’s Icon row and read by VoiceOver.",
            )
        case "cart.fill":
            FeatureText.string(
                key: "category.symbol.cart",
                defaultValue: "Cart",
                comment: "Category icon name, shown in the editor’s Icon row and read by VoiceOver.",
            )
        case "cup.and.saucer.fill":
            FeatureText.string(
                key: "category.symbol.cupAndSaucer",
                defaultValue: "Cup and Saucer",
                comment: "Category icon name, shown in the editor’s Icon row and read by VoiceOver.",
            )
        case "car.fill":
            FeatureText.string(
                key: "category.symbol.car",
                defaultValue: "Car",
                comment: "Category icon name, shown in the editor’s Icon row and read by VoiceOver.",
            )
        case "fuelpump.fill":
            FeatureText.string(
                key: "category.symbol.fuelPump",
                defaultValue: "Fuel Pump",
                comment: "Category icon name, shown in the editor’s Icon row and read by VoiceOver.",
            )
        case "tram.fill":
            FeatureText.string(
                key: "category.symbol.tram",
                defaultValue: "Tram",
                comment: "Category icon name, shown in the editor’s Icon row and read by VoiceOver.",
            )
        case "house.fill":
            FeatureText.string(
                key: "category.symbol.house",
                defaultValue: "House",
                comment: "Category icon name, shown in the editor’s Icon row and read by VoiceOver.",
            )
        case "bolt.fill":
            FeatureText.string(
                key: "category.symbol.lightningBolt",
                defaultValue: "Lightning Bolt",
                comment: "Category icon name, shown in the editor’s Icon row and read by VoiceOver.",
            )
        case "wifi":
            FeatureText.string(
                key: "category.symbol.wifi",
                defaultValue: "Wi-Fi",
                comment: "Category icon name, shown in the editor’s Icon row and read by VoiceOver.",
            )
        case "phone.fill":
            FeatureText.string(
                key: "category.symbol.phone",
                defaultValue: "Phone",
                comment: "Category icon name, shown in the editor’s Icon row and read by VoiceOver.",
            )
        case "cross.case.fill":
            FeatureText.string(
                key: "category.symbol.firstAidKit",
                defaultValue: "First Aid Kit",
                comment: "Category icon name, shown in the editor’s Icon row and read by VoiceOver.",
            )
        case "heart.fill":
            FeatureText.string(
                key: "category.symbol.heart",
                defaultValue: "Heart",
                comment: "Category icon name, shown in the editor’s Icon row and read by VoiceOver.",
            )
        case "bag.fill":
            FeatureText.string(
                key: "category.symbol.shoppingBag",
                defaultValue: "Shopping Bag",
                comment: "Category icon name, shown in the editor’s Icon row and read by VoiceOver.",
            )
        case "tshirt.fill":
            FeatureText.string(
                key: "category.symbol.tShirt",
                defaultValue: "T-Shirt",
                comment: "Category icon name, shown in the editor’s Icon row and read by VoiceOver.",
            )
        case "popcorn.fill":
            FeatureText.string(
                key: "category.symbol.popcorn",
                defaultValue: "Popcorn",
                comment: "Category icon name, shown in the editor’s Icon row and read by VoiceOver.",
            )
        case "gamecontroller.fill":
            FeatureText.string(
                key: "category.symbol.gameController",
                defaultValue: "Game Controller",
                comment: "Category icon name, shown in the editor’s Icon row and read by VoiceOver.",
            )
        case "person.fill":
            FeatureText.string(
                key: "category.symbol.person",
                defaultValue: "Person",
                comment: "Category icon name, shown in the editor’s Icon row and read by VoiceOver.",
            )
        case "pawprint.fill":
            FeatureText.string(
                key: "category.symbol.pawPrint",
                defaultValue: "Paw Print",
                comment: "Category icon name, shown in the editor’s Icon row and read by VoiceOver.",
            )
        case "graduationcap.fill":
            FeatureText.string(
                key: "category.symbol.graduationCap",
                defaultValue: "Graduation Cap",
                comment: "Category icon name, shown in the editor’s Icon row and read by VoiceOver.",
            )
        case "book.fill":
            FeatureText.string(
                key: "category.symbol.book",
                defaultValue: "Book",
                comment: "Category icon name, shown in the editor’s Icon row and read by VoiceOver.",
            )
        case "airplane":
            FeatureText.string(
                key: "category.symbol.plane",
                defaultValue: "Plane",
                comment: "Category icon name, shown in the editor’s Icon row and read by VoiceOver.",
            )
        case "doc.text.fill":
            FeatureText.string(
                key: "category.symbol.document",
                defaultValue: "Document",
                comment: "Category icon name, shown in the editor’s Icon row and read by VoiceOver.",
            )
        case "umbrella.fill":
            FeatureText.string(
                key: "category.symbol.umbrella",
                defaultValue: "Umbrella",
                comment: "Category icon name, shown in the editor’s Icon row and read by VoiceOver.",
            )
        case "creditcard.fill":
            FeatureText.string(
                key: "category.symbol.creditCard",
                defaultValue: "Credit Card",
                comment: "Category icon name, shown in the editor’s Icon row and read by VoiceOver.",
            )
        case "banknote.fill":
            FeatureText.string(
                key: "category.symbol.banknote",
                defaultValue: "Banknote",
                comment: "Category icon name, shown in the editor’s Icon row and read by VoiceOver.",
            )
        case "briefcase.fill":
            FeatureText.string(
                key: "category.symbol.briefcase",
                defaultValue: "Briefcase",
                comment: "Category icon name, shown in the editor’s Icon row and read by VoiceOver.",
            )
        case "percent":
            FeatureText.string(
                key: "category.symbol.percent",
                defaultValue: "Percent",
                comment: "Category icon name, shown in the editor’s Icon row and read by VoiceOver.",
            )
        case "gift.fill":
            FeatureText.string(
                key: "category.symbol.gift",
                defaultValue: "Gift",
                comment: "Category icon name, shown in the editor’s Icon row and read by VoiceOver.",
            )
        case "dumbbell.fill":
            FeatureText.string(
                key: "category.symbol.dumbbell",
                defaultValue: "Dumbbell",
                comment: "Category icon name, shown in the editor’s Icon row and read by VoiceOver.",
            )
        case "wrench.and.screwdriver.fill":
            FeatureText.string(
                key: "category.symbol.tools",
                defaultValue: "Tools",
                comment: "Category icon name, shown in the editor’s Icon row and read by VoiceOver.",
            )
        case "tag.fill":
            FeatureText.string(
                key: "category.symbol.tag",
                defaultValue: "Tag",
                comment: "Category icon name, shown in the editor’s Icon row and read by VoiceOver.",
            )
        case "ellipsis.circle.fill":
            FeatureText.string(
                key: "category.symbol.more",
                defaultValue: "More",
                comment: "Category icon name, shown in the editor’s Icon row and read by VoiceOver.",
            )
        case "plus.circle.fill":
            FeatureText.string(
                key: "category.symbol.plus",
                defaultValue: "Plus",
                comment: "Category icon name, shown in the editor’s Icon row and read by VoiceOver.",
            )
        default:
            nil
        }
    }

    /// The Icon row's name for a stored symbol the editor doesn't list (D292.2).
    static var currentIcon: String {
        FeatureText.string(
            "Current Icon",
            comment: "Category editor: the category’s own icon, listed first when it isn’t one of the usual icons.",
        )
    }
}
