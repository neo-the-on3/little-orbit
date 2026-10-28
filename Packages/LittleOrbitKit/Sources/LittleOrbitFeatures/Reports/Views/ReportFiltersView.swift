#if canImport(SwiftUI) && (os(iOS) || os(macOS))
    import LittleOrbitDomain
    import SwiftUI

    /// The report's period controls (#184): the preset picker with Custom Range, the From and To day pickers for a
    /// custom range, and ‹ period › to step one whole period back or on (⌘← and ⌘→ on macOS).
    struct ReportPeriodControls: View {
        let model: SpendingReportViewModel

        var body: some View {
            Picker(ReportText.period, selection: pick) {
                ForEach(model.periods) { period in
                    Text(model.periodName(period)).tag(Pick.preset(period))
                }
                Text(model.customRangeName).tag(Pick.custom)
            }
            .pickerStyle(.menu)
            if model.isCustomRange {
                DatePicker(model.customStartLabel, selection: start, displayedComponents: .date)
                DatePicker(model.customEndLabel, selection: end, displayedComponents: .date)
            }
            HStack {
                Button {
                    Task { await model.step(by: -1) }
                } label: {
                    Label(model.previousPeriodLabel, systemImage: "chevron.left")
                }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                Spacer()
                Text(model.periodTitle)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button {
                    Task { await model.step(by: 1) }
                } label: {
                    Label(model.nextPeriodLabel, systemImage: "chevron.right")
                }
                .keyboardShortcut(.rightArrow, modifiers: .command)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
        }

        enum Pick: Hashable {
            case preset(ReportPeriod)
            case custom
        }

        private var pick: Binding<Pick> {
            Binding(
                get: { model.period.map(Pick.preset) ?? .custom },
                set: { pick in
                    Task {
                        switch pick {
                        case .preset(let period): await model.select(period)
                        case .custom: await model.selectCustomRange()
                        }
                    }
                },
            )
        }

        private var start: Binding<Date> {
            Binding(
                get: { model.customStart },
                set: { day in Task { await model.selectCustomRange(from: day, to: model.customEnd) } },
            )
        }

        private var end: Binding<Date> {
            Binding(
                get: { model.customEnd },
                set: { day in Task { await model.selectCustomRange(from: model.customStart, to: day) } },
            )
        }
    }

    /// The account filter (#184): every account in the shown currency, hidden ones too, each ticked by default
    /// (D417). Unticking one removes its spending from the report and its drill-downs.
    struct ReportAccountsSheet: View {
        let model: SpendingReportViewModel
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            NavigationStack {
                List {
                    Section(model.currencyCode) {
                        ForEach(model.accounts) { option in
                            Toggle(isOn: included(option)) {
                                VStack(alignment: .leading) {
                                    Text(option.account.name)
                                        .fixedSize(horizontal: false, vertical: true)
                                    if option.account.isHidden {
                                        Text(model.hiddenAccountNote)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
                .navigationTitle(model.accountsTitle)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(role: .confirm) { dismiss() }
                    }
                }
            }
            #if os(macOS)
                .frame(minWidth: 320, minHeight: 280)
            #endif
        }

        private func included(_ option: ReportAccountOption) -> Binding<Bool> {
            Binding(
                get: { option.isIncluded },
                set: { included in Task { await model.setAccount(option.id, included: included) } },
            )
        }
    }

    /// “Couldn’t Load Report” / “Try again.” with a Try Again button (D318.5).
    struct ReportLoadFailedView: View {
        let model: SpendingReportViewModel
        let retry: () async -> Void

        var body: some View {
            ContentUnavailableView {
                Label(model.loadFailedTitle, systemImage: "exclamationmark.triangle")
            } description: {
                Text(model.loadFailedMessage)
            } actions: {
                Button(model.tryAgainButton) {
                    Task { await retry() }
                }
            }
        }
    }
#endif
