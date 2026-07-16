import SwiftUI

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
  @Environment(\.dynamicTypeSize) private var dts

  var isWide: Bool = false
  var showsValidationError: Bool = false
  var isSaving: Bool = false

  @State private var title = "14U Summer Program"
  @State private var notes = ""
  @State private var amountCents = 14_900
  @State private var category = "program"

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: HP.Space.md) {
        HPWorkspaceHeader("New payment request",
                          orgLabel: HPSample.orgIdentity.name,
                          context: "Draft · not yet sent",
                          identity: HPSample.orgIdentity)

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

        // Action row — one primary. Stacks full-width at AX3.
        HPCard {
          let layout = dts.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: HP.Space.sm))
            : AnyLayout(HStackLayout(alignment: .center, spacing: HP.Space.sm))
          layout {
            HPButton(title: "Send request", variant: .primary, size: .lg,
                     isLoading: isSaving,
                     fullWidth: dts.isAccessibilitySize)
            HPButton(title: "Cancel", variant: .secondary, size: .lg,
                     fullWidth: dts.isAccessibilitySize)
            if !dts.isAccessibilitySize { Spacer(minLength: 0) }
          }
        }
      }
      .padding(HP.Space.md)
      .frame(maxWidth: isWide ? 720 : .infinity, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: isWide ? .center : .leading)
    }
    .background(HP.Color.bg)
  }
}

#Preview("Form — iPhone") { HPFormScreenTemplate() }
#Preview("Form — iPad/macOS") { HPFormScreenTemplate(isWide: true) }
#Preview("Form — validation error") { HPFormScreenTemplate(showsValidationError: true) }
