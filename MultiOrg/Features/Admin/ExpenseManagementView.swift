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
    DHDCard {
      VStack(alignment: .leading, spacing: 10) {
        DHDSectionHeader("Expenses") {
          HStack(spacing: 8) {
            Button(action: onRefresh) { Image(systemName: "arrow.clockwise") }
              .buttonStyle(.borderless)
              .disabled(isLoading || viewModel.isExpenseMutationInFlight)
              .accessibilityLabel("Refresh Expenses")
            if canMutate {
              Button {
                viewModel.clearExpenseMessage()
                editor = ExpenseEditorPresentation(expense: nil)
              } label: {
                Label("Add Expense", systemImage: "plus")
              }
              .buttonStyle(.borderedProminent)
              .disabled(viewModel.isExpenseMutationInFlight)
            }
          }
        }

        if supportMode {
          Label(
            "Platform Support — read-only financial access",
            systemImage: "lock.shield"
          )
          .font(.footnote.weight(.semibold))
          .foregroundStyle(DHDTheme.textSecondary)
        }

        if let success = viewModel.expenseSuccessMessage {
          Text(success).font(.footnote).foregroundStyle(.green)
        }
        if let mutationError = viewModel.expenseMutationError {
          Text(mutationError).font(.footnote).foregroundStyle(.red)
        }

        if let expenses, !expenses.isEmpty {
          HStack(spacing: 10) {
            TextField("Search expenses", text: $searchText)
              .textFieldStyle(.roundedBorder)
            Picker("Category", selection: $selectedCategory) {
              Text("All Categories").tag("all")
              ForEach(categories, id: \.self) { category in
                Text(category).tag(category)
              }
            }
            .frame(maxWidth: 220)
          }
        }

        if isLoading, expenses == nil {
          HStack {
            ProgressView()
            Text("Loading expenses…").foregroundStyle(DHDTheme.textSecondary)
          }
        } else if let errorMessage {
          VStack(alignment: .leading, spacing: 8) {
            Text(errorMessage).font(.footnote).foregroundStyle(.red)
            Button("Try Again", action: onRefresh).buttonStyle(.bordered)
          }
        } else if let expenses, expenses.isEmpty {
          Text("No expenses in this date range.")
            .foregroundStyle(DHDTheme.textSecondary)
        } else if filteredExpenses.isEmpty {
          Text("No expenses match the current search and category filter.")
            .foregroundStyle(DHDTheme.textSecondary)
        } else {
          ForEach(filteredExpenses) { expense in
            ExpenseRow(
              expense: expense,
              canMutate: canMutate,
              mutationDisabled: viewModel.isExpenseMutationInFlight,
              onEdit: {
                viewModel.clearExpenseMessage()
                editor = ExpenseEditorPresentation(expense: expense)
              },
              onArchive: { archiveCandidate = expense }
            )
            Divider().overlay(DHDTheme.separator.opacity(0.3))
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
}

struct ExpenseRow: View {
  let expense: FinanceExpense
  let canMutate: Bool
  let mutationDisabled: Bool
  let onEdit: () -> Void
  let onArchive: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 3) {
        Text(expense.description ?? "Expense").font(.headline)
        Text([expense.vendor, expense.category, expense.expense_date].compactMap { $0 }.joined(separator: " • "))
          .font(.caption)
          .foregroundStyle(DHDTheme.textSecondary)
        if let notes = expense.notes, !notes.isEmpty {
          Text(notes).font(.caption2).foregroundStyle(DHDTheme.textSecondary)
            .lineLimit(2)
        }
      }
      Spacer()
      VStack(alignment: .trailing, spacing: 6) {
        Text(expense.money.formatted()).font(.subheadline.weight(.semibold))
        if canMutate {
          HStack(spacing: 8) {
            Button("Edit", action: onEdit).buttonStyle(.borderless)
            Button("Archive", role: .destructive, action: onArchive)
              .buttonStyle(.borderless)
          }
          .disabled(mutationDisabled)
        }
      }
    }
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
      Form {
        Section("Expense") {
          TextField("Category", text: $form.category)
          TextField("Description", text: $form.description)
          TextField("Amount", text: $form.amountText)
          #if os(iOS)
          .keyboardType(.decimalPad)
          #endif
          DatePicker("Expense Date", selection: $form.expenseDate, displayedComponents: .date)
          TextField("Vendor (optional)", text: $form.vendor)
          VStack(alignment: .leading, spacing: 6) {
            Text("Notes (optional)").font(.caption).foregroundStyle(DHDTheme.textSecondary)
            TextEditor(text: $form.notes).frame(minHeight: 90)
          }
          LabeledContent("Currency", value: form.normalizedCurrency.uppercased())
        }

        Section {
          Text("Receipt attachments are not available yet.")
            .font(.footnote)
            .foregroundStyle(DHDTheme.textSecondary)
        }

        if let validationError = form.validationError {
          Section {
            Text(validationError).font(.footnote).foregroundStyle(.red)
          }
        } else if let mutationError {
          Section {
            Text(mutationError).font(.footnote).foregroundStyle(.red)
          }
        }
      }
      .navigationTitle(expense == nil ? "Add Expense" : "Edit Expense")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }.disabled(isSubmitting)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(isSubmitting ? "Saving…" : "Save") {
            guard !isSubmitting else { return }
            isSubmitting = true
            Task {
              let succeeded = await onSave(form)
              isSubmitting = false
              if succeeded { dismiss() }
            }
          }
          .disabled(!form.isValid || isSubmitting || isMutationInFlight)
        }
      }
    }
    #if os(macOS)
    .frame(minWidth: 520, minHeight: 560)
    #endif
  }
}

private struct ExpenseEditorPresentation: Identifiable {
  let id = UUID()
  let expense: FinanceExpense?
}
