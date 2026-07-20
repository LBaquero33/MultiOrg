import SwiftUI

/// Reusable presentation shell for a single-record form.
///
/// The caller owns every binding, validation rule, callback, keyboard policy,
/// and persistence side effect. This layout owns only the canonical ordering,
/// 720-point single-column cap, and accessibility action relayout.
struct HPFormScreenLayout<Header: View, Sections: View, PrimaryAction: View, SecondaryAction: View>: View {
  private let widthMode: HPScreenWidthMode
  private let maxContentWidth: CGFloat?
  private let header: (HPScreenLayoutContext) -> Header
  private let sections: (HPScreenLayoutContext) -> Sections
  private let primaryAction: (HPScreenLayoutContext) -> PrimaryAction
  private let secondaryAction: (HPScreenLayoutContext) -> SecondaryAction

  init(
    widthMode: HPScreenWidthMode = .automatic,
    maxContentWidth: CGFloat? = 720,
    @ViewBuilder header: @escaping (HPScreenLayoutContext) -> Header,
    @ViewBuilder sections: @escaping (HPScreenLayoutContext) -> Sections,
    @ViewBuilder primaryAction: @escaping (HPScreenLayoutContext) -> PrimaryAction,
    @ViewBuilder secondaryAction: @escaping (HPScreenLayoutContext) -> SecondaryAction
  ) {
    self.widthMode = widthMode
    self.maxContentWidth = maxContentWidth
    self.header = header
    self.sections = sections
    self.primaryAction = primaryAction
    self.secondaryAction = secondaryAction
  }

  var body: some View {
    HPScreenScaffold(widthMode: widthMode, maxContentWidth: maxContentWidth) { context in
      VStack(alignment: .leading, spacing: HP.Space.md) {
        header(context)
        sections(context)
        HPCard {
          actionRow(context)
        }
      }
    }
  }

  @ViewBuilder
  private func actionRow(_ context: HPScreenLayoutContext) -> some View {
    let layout = context.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: HP.Space.sm))
      : AnyLayout(HStackLayout(alignment: .center, spacing: HP.Space.sm))
    layout {
      primaryAction(context)
        .frame(maxWidth: context.isAccessibilitySize ? .infinity : nil, alignment: .leading)
      secondaryAction(context)
        .frame(maxWidth: context.isAccessibilitySize ? .infinity : nil, alignment: .leading)
      if !context.isAccessibilitySize { Spacer(minLength: 0) }
    }
  }
}

/// Template 4 — **Form / editor screen**.
///
/// Purpose: create or edit one record. Anatomy: header → grouped
/// `HPFormField`/`HPMoneyField` sections → validation → sticky primary action.
///
/// Rules:
/// - Money is **always** `HPMoneyField` (integer cents) — never a raw `TextField`.
/// - Validation is inline on the field (`error:`), never only in an alert.
/// - Exactly one `.primary` submit; Cancel is `.secondary`.
/// - Forms are single-column at every width — never side-by-side fields.
struct HPFormScreenTemplate: View {
  var isWide: Bool = false
  var showsValidationError: Bool = false
  var isSaving: Bool = false

  @State private var title = "14U Summer Program"
  @State private var notes = ""
  @State private var amountCents = 14_900
  @State private var category = "program"

  var body: some View {
    HPFormScreenLayout(widthMode: isWide ? .automatic : .compact) { _ in
        HPWorkspaceHeader("New payment request",
                          orgLabel: HPSample.orgIdentity.name,
                          context: "Draft · not yet sent",
                          identity: HPSample.orgIdentity)
    } sections: { _ in
        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.md) {
            HPSectionHeader("Details")
            HPFormField(label: "Title", text: $title, placeholder: "e.g. 14U Summer Program",
                        helper: "Shown to the parent on the invoice.")
            HPMoneyField(label: "Amount", cents: $amountCents,
                         helper: showsValidationError ? nil : "Charged once when the parent pays.",
                         error: showsValidationError ? "Amount must be greater than $0." : nil)
            VStack(alignment: .leading, spacing: 6) {
              Text("Category")
                .font(HP.Font.eyebrow).tracking(HP.Font.eyebrowTracking)
                .foregroundStyle(HP.Color.textMuted)
              HPSegmentedControl(
                options: [(value: "program", label: "Program"),
                          (value: "lesson", label: "Lesson"),
                          (value: "fee", label: "Fee")],
                selection: $category
              )
            }
            HPFormField(label: "Notes (optional)", text: $notes, kind: .multiline,
                        placeholder: "Anything the parent should know")
          }
        }
    } primaryAction: { context in
      HPButton(title: "Send request", variant: .primary, size: .lg,
               isLoading: isSaving,
               fullWidth: context.isAccessibilitySize)
    } secondaryAction: { context in
      HPButton(title: "Cancel", variant: .secondary, size: .lg,
               fullWidth: context.isAccessibilitySize)
    }
  }
}

#Preview("Form — iPhone") { HPFormScreenTemplate() }
#Preview("Form — iPad/macOS") { HPFormScreenTemplate(isWide: true) }
#Preview("Form — validation error") { HPFormScreenTemplate(showsValidationError: true) }
