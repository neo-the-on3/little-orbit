#if canImport(SwiftUI) && os(iOS)
    import LittleOrbitDomain
    import LittleOrbitTheme
    import SwiftUI

    /// The entry sheet's amount on iOS (D163): a decimal-pad field with a row of + − × ÷ = above the keyboard,
    /// shown only while the amount is focused. While editing, the field shows the sum as typed; otherwise the
    /// signed amount. After "=", the sum just worked out shows above either. The sum is worked out on "=" or
    /// when focus leaves the field, and an error shows under the field while Save stays off. The amount never
    /// truncates: at accessibility sizes it may shrink to half, else to 70% (Tester's #87 B1).
    struct TransactionAmountField: View {
        @Bindable var model: TransactionFormViewModel
        var focus: FocusState<TransactionFormView.FormField?>.Binding
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        private var isEditing: Bool { focus.wrappedValue == .amount }

        var body: some View {
            VStack(alignment: .trailing, spacing: Spacing.spaceHalf) {
                // After "=" the sum stays above the result, in the field or out of it (Tester's #87 recheck, 6).
                if let line = model.expressionLine, model.amountError == nil {
                    Text(line)
                        .font(.theme(Typography.IOS.footnote))
                        .foregroundStyle(Color(ThemeColor.labelSecondary))
                }
                ZStack(alignment: .trailing) {
                    field
                    if !isEditing {
                        shownAmount
                    }
                }
                if let error = model.amountError {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(.theme(Typography.IOS.footnote))
                        .foregroundStyle(Color(ThemeColor.destructiveDefault))
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .toolbar {
                // The five keys stay in one HStack, so none overflows into a More menu on a narrow iPhone
                // (Tester's #87 recheck, bug 5). The group always has content: other fields get a trailing
                // Done that hides the keyboard (D171, D172 U4).
                ToolbarItemGroup(placement: .keyboard) {
                    if isEditing {
                        HStack(spacing: Spacing.space1) {
                            operatorButton("+", spoken: "plus", key: .add)
                            operatorButton("−", spoken: "minus", key: .subtract)
                            operatorButton("×", spoken: "times", key: .multiply)
                            operatorButton("÷", spoken: "divide", key: .divide)
                            operatorButton("=", spoken: "equals", key: .equals)
                        }
                    } else {
                        Spacer()
                        Button("Done") { focus.wrappedValue = nil }
                    }
                }
            }
            .onChange(of: focus.wrappedValue) { old, new in
                if old == .amount, new != .amount {
                    model.commitAmount()
                }
            }
        }

        private var field: some View {
            TextField("Amount", text: $model.expressionInput, prompt: Text("0"))
                .keyboardType(.decimalPad)
                .focused(focus, equals: .amount)
                .multilineTextAlignment(.trailing)
                .font(.theme(Typography.Amount.iOSHero))
                .foregroundStyle(model.amountTone.color)
                .lineLimit(1)
                .minimumScaleFactor(amountScale)
                .opacity(isEditing ? 1 : 0)
                .accessibilityLabel("Amount")
                .accessibilityHidden(!isEditing)
        }

        /// The signed amount, or the sum that didn't work out. Tapping it edits the amount.
        private var shownAmount: some View {
            let text = model.amountError == nil ? model.amountText : model.expressionText
            return Text(text)
                .font(.theme(Typography.Amount.iOSHero))
                .foregroundStyle(model.amountTone.color)
                .lineLimit(1)
                .minimumScaleFactor(amountScale)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .contentShape(Rectangle())
                .onTapGesture { focus.wrappedValue = .amount }
                .accessibilityLabel("Amount")
                .accessibilityValue(text)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(named: "Edit amount") { focus.wrappedValue = .amount }
        }

        private var amountScale: CGFloat { dynamicTypeSize.isAccessibilitySize ? 0.5 : 0.7 }

        private func operatorButton(_ symbol: String, spoken: String, key: KeypadKey) -> some View {
            Button {
                model.press(key)
            } label: {
                Text(symbol)
                    .font(.theme(Typography.IOS.title3))
                    .frame(minWidth: Layout.minimumTargetIOS, minHeight: Layout.minimumTargetIOS)
            }
            .accessibilityLabel(spoken)
        }
    }
#endif
