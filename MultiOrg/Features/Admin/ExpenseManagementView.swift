import SwiftUI

struct ExpenseManagementView: View {
  let organizationId: UUID
  let supportMode: Bool
  let defaultCurrency: String
  let expenses: [FinanceExpense]?
  let authorizationSource: FinanceAuthorizationSource?
  let isLoading: Bool
  let errorMessage: String?
  @ObservedObject var viewModel: FinanceDashboardViewModel
  let service: (any FinanceDashboardServicing)?
  let onRefresh: () -> Void

  @State private var searchText = ""
  @State private var selectedCategory = "all"
  @State private var editor: ExpenseEditorPresentation?
  @State private var archiveCandidate: FinanceExpense?

  private var canMutate: Bool {
    FinanceExpenseClientAuthorization.canMutate(
      authorizationSource: authorizationSource,
      supportMode: supportMode
    )
  }

  private var categories: [String] {
    Array(Set((expenses ?? []).compactMap { expense in
      let value = expense.category?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      return value.isEmpty ? nil : value
    })).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
  }

  private var filteredExpenses: [FinanceExpense] {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    return (expenses ?? []).filter { expense in
      let matchesCategory = selectedCategory == "all" ||
        expense.category?.caseInsensitiveCompare(selectedCategory) == .orderedSame
      guard matchesCategory else { return false }
      guard !query.isEmpty else { return true }
      return [expense.description, expense.category, expense.vendor, expense.notes]
        .compactMap { $0 }
        .contains { $0.localizedCaseInsensitiveContains(query) }
    }
  }

  var body: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.md) {
        HPSectionHeader("Expenses")
        ViewThatFits(in: .horizontal) {
          HStack(spacing: HP.Space.sm) {
            expenseActions(fullWidth: false)
            Spacer(minLength: 0)
          }
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            expenseActions(fullWidth: true)
          }
        }

        if supportMode {
          HStack(alignment: .top, spacing: HP.Space.sm) {
            Image(systemName: "lock.shield")
              .foregroundStyle(HP.Color.accent)
              .accessibilityHidden(true)
            Text("Platform Support — read-only financial access")
              .font(HP.Font.caption.weight(.semibold))
              .foregroundStyle(HP.Color.textMuted)
              .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            HPStatusBadge(text: "Read-only", kind: .gold)
          }
          .accessibilityElement(children: .combine)
        }

        if let success = viewModel.expenseSuccessMessage {
          expenseFeedback(success, kind: .success)
        }
        if let mutationError = viewModel.expenseMutationError {
          expenseFeedback(mutationError, kind: .danger)
        }

        if let expenses, !expenses.isEmpty {
          ViewThatFits(in: .horizontal) {
            HStack(spacing: HP.Space.sm) {
              HPSearchBar(text: $searchText, placeholder: "Search expenses")
              categoryMenu(fullWidth: false)
            }
            VStack(alignment: .leading, spacing: HP.Space.sm) {
              HPSearchBar(text: $searchText, placeholder: "Search expenses")
              categoryMenu(fullWidth: true)
            }
          }
        }

        if isLoading, expenses == nil {
          HPLoadingState(text: "Loading expenses…")
        } else if let errorMessage {
          HPErrorState(message: errorMessage, retryTitle: "Try Again", onRetry: onRefresh)
        } else if let expenses, expenses.isEmpty {
          HPEmptyState(
            title: "No expenses",
            message: "No expenses were recorded in this date range.",
            systemImage: "receipt"
          )
        } else if filteredExpenses.isEmpty {
          HPEmptyState(
            title: "No matching expenses",
            message: "Try changing the search or category filter.",
            systemImage: "magnifyingglass"
          )
        } else {
          ForEach(Array(filteredExpenses.enumerated()), id: \.element.id) { index, expense in
            ExpenseRow(
              expense: expense,
              canMutate: canMutate,
              mutationDisabled: isLoading || viewModel.isExpenseMutationInFlight,
              onEdit: {
                viewModel.clearExpenseMessage()
                editor = ExpenseEditorPresentation(expense: expense)
              },
              onArchive: { archiveCandidate = expense }
            )
            if index < filteredExpenses.count - 1 {
              Divider().overlay(HP.Color.border.opacity(0.5))
            }
          }
        }
      }
    }
    .sheet(item: $editor) { presentation in
      ExpenseEditorSheet(
        expense: presentation.expense,
        defaultCurrency: defaultCurrency,
        mutationError: viewModel.expenseMutationError,
        isMutationInFlight: viewModel.isExpenseMutationInFlight
      ) { form in
        if let expense = presentation.expense {
          return await viewModel.updateExpense(
            expense,
            form: form,
            organizationId: organizationId,
            supportMode: supportMode,
            service: service
          )
        }
        return await viewModel.createExpense(
          form: form,
          organizationId: organizationId,
          supportMode: supportMode,
          service: service
        )
      }
    }
    .alert(
      "Archive Expense?",
      isPresented: Binding(
        get: { archiveCandidate != nil },
        set: { if !$0 { archiveCandidate = nil } }
      ),
      presenting: archiveCandidate
    ) { expense in
      Button("Archive", role: .destructive) {
        Task {
          if await viewModel.archiveExpense(
            expense,
            organizationId: organizationId,
            supportMode: supportMode,
            service: service
          ) {
            archiveCandidate = nil
          }
        }
      }
      Button("Cancel", role: .cancel) { archiveCandidate = nil }
    } message: { expense in
      Text("Archive \(expense.description ?? "this expense")? It will be excluded from finance totals and retained for audit history.")
    }
    .onChange(of: organizationId) { _, _ in
      searchText = ""
      selectedCategory = "all"
      editor = nil
      archiveCandidate = nil
      viewModel.clearExpenseMessage()
    }
    .onChange(of: categories) { _, updated in
      if selectedCategory != "all" && !updated.contains(selectedCategory) {
        selectedCategory = "all"
      }
    }
  }

  @ViewBuilder
  private func expenseActions(fullWidth: Bool) -> some View {
    HPButton(
      title: "Refresh",
      systemImage: "arrow.clockwise",
      variant: .secondary,
      size: .sm,
      fullWidth: fullWidth,
      action: onRefresh
    )
    .disabled(isLoading || viewModel.isExpenseMutationInFlight)
    .accessibilityLabel("Refresh Expenses")

    if canMutate {
      HPButton(
        title: "Add Expense",
        systemImage: "plus",
        variant: .primary,
        size: .sm,
        fullWidth: fullWidth,
        action: {
          viewModel.clearExpenseMessage()
          editor = ExpenseEditorPresentation(expense: nil)
        }
      )
      .disabled(isLoading || viewModel.isExpenseMutationInFlight)
    }
  }

  private func expenseFeedback(_ message: String, kind: HPStatusKind) -> some View {
    HStack(alignment: .top, spacing: HP.Space.xs) {
      Image(systemName: kind == .success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
        .foregroundStyle(kind.color)
        .accessibilityHidden(true)
      Text(message)
        .font(HP.Font.caption)
        .foregroundStyle(HP.Color.text)
        .fixedSize(horizontal: false, vertical: true)
    }
    .accessibilityElement(children: .combine)
  }

  private func categoryMenu(fullWidth: Bool) -> some View {
    Menu {
      Button {
        selectedCategory = "all"
      } label: {
        if selectedCategory == "all" {
          Label("All Categories", systemImage: "checkmark")
        } else {
          Text("All Categories")
        }
      }
      ForEach(categories, id: \.self) { category in
        Button {
          selectedCategory = category
        } label: {
          if selectedCategory == category {
            Label(category, systemImage: "checkmark")
          } else {
            Text(category)
          }
        }
      }
    } label: {
      HStack(spacing: HP.Space.sm) {
        Text(selectedCategory == "all" ? "All Categories" : selectedCategory)
          .font(HP.Font.callout)
          .foregroundStyle(HP.Color.text)
          .lineLimit(1)
        Spacer(minLength: HP.Space.sm)
        Image(systemName: "chevron.up.chevron.down")
          .font(HP.Font.caption)
          .foregroundStyle(HP.Color.textMuted)
          .accessibilityHidden(true)
      }
      .padding(.horizontal, HP.Space.sm)
      .frame(maxWidth: fullWidth ? .infinity : 220, minHeight: 44)
      .background(
        RoundedRectangle(cornerRadius: HP.Radius.md, style: .continuous)
          .fill(HP.Color.input)
      )
      .overlay(
        RoundedRectangle(cornerRadius: HP.Radius.md, style: .continuous)
          .strokeBorder(HP.Color.border, lineWidth: 1)
          .allowsHitTesting(false)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Category")
    .accessibilityValue(selectedCategory == "all" ? "All Categories" : selectedCategory)
  }
}

struct ExpenseRow: View {
  let expense: FinanceExpense
  let canMutate: Bool
  let mutationDisabled: Bool
  let onEdit: () -> Void
  let onArchive: () -> Void

  var body: some View {
    ViewThatFits(in: .horizontal) {
      compactRow
      stackedRow
    }
    .padding(.vertical, HP.Space.xs)
  }

  private var compactRow: some View {
    HStack(alignment: .top, spacing: 12) {
      expenseDetails
      Spacer(minLength: HP.Space.sm)
      VStack(alignment: .trailing, spacing: 6) {
        expenseAmount
        mutationActions(fullWidth: false)
      }
    }
  }

  private var stackedRow: some View {
    VStack(alignment: .leading, spacing: HP.Space.sm) {
      expenseDetails
      expenseAmount
      mutationActions(fullWidth: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var expenseDetails: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(expense.description ?? "Expense")
        .font(HP.Font.headline)
        .foregroundStyle(HP.Color.text)
        .fixedSize(horizontal: false, vertical: true)
      Text(
        [expense.vendor, expense.category, expense.expense_date]
          .compactMap { $0 }
          .joined(separator: " • ")
      )
      .font(HP.Font.caption)
      .foregroundStyle(HP.Color.textMuted)
      .fixedSize(horizontal: false, vertical: true)
      if let notes = expense.notes, !notes.isEmpty {
        Text(notes)
          .font(HP.Font.caption)
          .foregroundStyle(HP.Color.textMuted)
          .lineLimit(2)
      }
    }
  }

  private var expenseAmount: some View {
    Text(expense.money.formatted())
      .font(HP.Font.callout.weight(.semibold))
      .foregroundStyle(HP.Color.text)
      .fixedSize(horizontal: false, vertical: true)
  }

  @ViewBuilder
  private func mutationActions(fullWidth: Bool) -> some View {
    if canMutate {
      if fullWidth {
        VStack(alignment: .leading, spacing: HP.Space.xs) {
          editButton(fullWidth: true)
          archiveButton(fullWidth: true)
        }
      } else {
        HStack(spacing: HP.Space.xs) {
          editButton(fullWidth: false)
          archiveButton(fullWidth: false)
        }
      }
    }
  }

  private func editButton(fullWidth: Bool) -> some View {
    HPButton(
      title: "Edit",
      systemImage: "pencil",
      variant: .tertiary,
      size: .sm,
      fullWidth: fullWidth,
      action: onEdit
    )
    .disabled(mutationDisabled)
  }

  private func archiveButton(fullWidth: Bool) -> some View {
    HPButton(
      title: "Archive",
      systemImage: "archivebox",
      variant: .destructive,
      size: .sm,
      fullWidth: fullWidth,
      action: onArchive
    )
    .disabled(mutationDisabled)
  }
}

struct ExpenseEditorSheet: View {
  let expense: FinanceExpense?
  let defaultCurrency: String
  let mutationError: String?
  let isMutationInFlight: Bool
  let onSave: (FinanceExpenseFormModel) async -> Bool

  @Environment(\.dismiss) private var dismiss
  @State private var form: FinanceExpenseFormModel
  @State private var isSubmitting = false

  private struct DecimalKeyboard: ViewModifier {
    func body(content: Content) -> some View {
      #if canImport(UIKit)
      return content.keyboardType(.decimalPad)
      #else
      return content
      #endif
    }
  }

  init(
    expense: FinanceExpense?,
    defaultCurrency: String,
    mutationError: String?,
    isMutationInFlight: Bool,
    onSave: @escaping (FinanceExpenseFormModel) async -> Bool
  ) {
    self.expense = expense
    self.defaultCurrency = defaultCurrency
    self.mutationError = mutationError
    self.isMutationInFlight = isMutationInFlight
    self.onSave = onSave
    _form = State(initialValue: expense.map(FinanceExpenseFormModel.init) ??
      FinanceExpenseFormModel(currency: defaultCurrency))
  }

  var body: some View {
    NavigationStack {
      HPFormScreenLayout { _ in
        HPWorkspaceHeader(
          expense == nil ? "Add Expense" : "Edit Expense",
          context: "\(form.normalizedCurrency.uppercased()) • Finance"
        )
      } sections: { _ in
        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.md) {
            HPSectionHeader("Expense")
            HPFormField(
              label: "Category",
              text: $form.category,
              placeholder: "Expense category",
              isEnabled: !isSubmitting
            )
            HPFormField(
              label: "Description",
              text: $form.description,
              placeholder: "What was purchased?",
              isEnabled: !isSubmitting
            )
            HPFormField(
              label: "Amount",
              text: $form.amountText,
              placeholder: "0.00",
              helper: "Enter the amount in \(form.normalizedCurrency.uppercased()).",
              isEnabled: !isSubmitting
            )
            .modifier(DecimalKeyboard())
            DatePicker(
              "Expense Date",
              selection: $form.expenseDate,
              displayedComponents: .date
            )
            .font(HP.Font.body)
            .foregroundStyle(HP.Color.text)
            .tint(HP.Color.accent)
            .frame(minHeight: 44)
            .disabled(isSubmitting)
            HPFormField(
              label: "Vendor (optional)",
              text: $form.vendor,
              placeholder: "Vendor name",
              isEnabled: !isSubmitting
            )
            HPFormField(
              label: "Notes (optional)",
              text: $form.notes,
              kind: .multiline,
              placeholder: "Expense notes",
              isEnabled: !isSubmitting
            )
            LabeledContent("Currency", value: form.normalizedCurrency.uppercased())
              .font(HP.Font.callout)
              .foregroundStyle(HP.Color.text)
              .frame(minHeight: 44)
          }
        }

        HPCard(style: .flat) {
          Label(
            "Receipt attachments are not available yet.",
            systemImage: "paperclip"
          )
          .font(HP.Font.caption)
          .foregroundStyle(HP.Color.textMuted)
          .fixedSize(horizontal: false, vertical: true)
        }

        if let validationError = form.validationError {
          HPCard(style: .flat) {
            HPErrorState(title: "Check expense details", message: validationError)
          }
        } else if let mutationError {
          HPCard(style: .flat) {
            HPErrorState(title: "Expense could not be saved", message: mutationError)
          }
        }
      } primaryAction: { context in
        HPButton(
          title: isSubmitting ? "Saving…" : "Save",
          systemImage: "checkmark",
          variant: .primary,
          size: .lg,
          isLoading: isSubmitting,
          fullWidth: context.isAccessibilitySize,
          action: submit
        )
        .disabled(!form.isValid || isSubmitting || isMutationInFlight)
      } secondaryAction: { context in
        HPButton(
          title: "Cancel",
          variant: .secondary,
          size: .lg,
          fullWidth: context.isAccessibilitySize,
          action: { dismiss() }
        )
        .disabled(isSubmitting)
      }
      .navigationTitle(expense == nil ? "Add Expense" : "Edit Expense")
    }
    #if os(macOS)
    .onExitCommand {
      guard !isSubmitting else { return }
      dismiss()
    }
    .frame(minWidth: 520, minHeight: 560)
    #endif
  }

  private func submit() {
    guard !isSubmitting else { return }
    isSubmitting = true
    Task {
      let succeeded = await onSave(form)
      isSubmitting = false
      if succeeded { dismiss() }
    }
  }
}

private struct ExpenseEditorPresentation: Identifiable {
  let id = UUID()
  let expense: FinanceExpense?
}
