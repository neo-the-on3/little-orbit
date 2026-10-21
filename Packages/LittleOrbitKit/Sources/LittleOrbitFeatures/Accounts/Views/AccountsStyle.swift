#if canImport(SwiftUI) && (os(iOS) || os(macOS))
    import LittleOrbitTheme
    import SwiftUI

    extension AmountTone {
        /// The `money/*` token for a balance.
        var color: Color {
            switch self {
            case .neutral: Color(ThemeColor.labelPrimary)
            case .positive: Color(ThemeColor.moneyPositive)
            case .negative: Color(ThemeColor.moneyNegative)
            }
        }
    }

    extension HomeDestination {
        /// The category hue behind each home row icon (Figma node 14:1424).
        var tint: Color {
            switch self {
            case .budgets: Color(CategoryColor.orange)
            case .scheduled: Color(CategoryColor.blue)
            case .reports: Color(CategoryColor.amber)
            }
        }
    }

    /// The tinted square account icon used in rows and the detail header.
    struct AccountIconView: View {
        let symbolName: String
        var size: Double = 32

        var body: some View {
            Image(systemName: symbolName)
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(Color(ThemeColor.accentOnTint))
                .frame(width: size, height: size)
                .background(Color(ThemeColor.accentTint), in: RoundedRectangle(cornerRadius: Radius.small))
                .accessibilityHidden(true)
        }
    }

    /// The filled circle icon for the Budgets, Scheduled and Reports rows.
    struct HomeIconView: View {
        let destination: HomeDestination
        var size: Double = 32

        var body: some View {
            Image(systemName: destination.symbolName)
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(Color(ThemeColor.labelOnColor))
                .frame(width: size, height: size)
                .background(destination.tint, in: Circle())
                .accessibilityHidden(true)
        }
    }

    /// The red count badge (D104): hidden at 0, "99+" above 99.
    struct CountBadgeView: View {
        let text: String

        var body: some View {
            Text(text)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color(ThemeColor.labelOnColor))
                .padding(.horizontal, Spacing.space2)
                .padding(.vertical, Spacing.spaceHalf)
                .background(Color(ThemeColor.destructiveFill), in: Capsule())
        }
    }

    /// A small neutral capsule such as "Hidden" or "Excluded".
    struct StatusTag: View {
        let text: String

        var body: some View {
            Text(text)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Color(ThemeColor.statusNeutral))
                .padding(.horizontal, Spacing.space1 + Spacing.spaceHalf)
                .padding(.vertical, Spacing.spaceHalf)
                .background(Color(ThemeColor.statusNeutralBg), in: Capsule())
        }
    }

    /// Where a list or sidebar row leads.
    enum AccountsRoute: Hashable {
        case allTransactions
        case home(HomeDestination)
        case account(UUID)
    }

    /// The state for the account form sheet. The view model is made once, when the sheet is requested
    /// (`AccountsFeature.makeForm`), rather than each time SwiftUI evaluates the sheet's content.
    struct AccountFormSheet: Identifiable {
        let id = UUID()
        let model: AccountFormViewModel
    }

    /// A screen that a later issue fills in.
    struct UpcomingFeatureView: View {
        let title: String
        let systemImage: String
        let message: String

        var body: some View {
            ContentUnavailableView(title, systemImage: systemImage, description: Text(message))
                .navigationTitle(title)
        }
    }
#endif
