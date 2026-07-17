import SwiftUI

/// Text input field with label, helper/error line, and a visible gold focus
/// ring. Unifies `.roundedBorder` fields + `DHDFormRow`.
struct HPFormField: View {
  enum Kind { case text, secure, multiline }

  let label: String
  @Binding var text: String
  var kind: Kind = .text
  var placeholder: String = ""
  var helper: String? = nil
  var error: String? = nil
  var isEnabled: Bool = true

  @FocusState private var focused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(label.uppercased())
        .font(HP.Font.eyebrow).tracking(HP.Font.eyebrowTracking)
        .foregroundStyle(HP.Color.textMuted)
        .fixedSize(horizontal: false, vertical: true)

      field
        .font(HP.Font.body)
        .foregroundStyle(HP.Color.text)
        .focused($focused)
        .disabled(!isEnabled)
        .padding(.horizontal, HP.Space.sm)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: HP.Radius.md, style: .continuous).fill(HP.Color.input))
        .overlay(
          RoundedRectangle(cornerRadius: HP.Radius.md, style: .continuous)
            .strokeBorder(borderColor, lineWidth: (focused || error != nil) ? 2 : 1)
            .allowsHitTesting(false)
        )

      if let error {
        Text(error).font(HP.Font.caption).foregroundStyle(HP.Color.danger)
          .fixedSize(horizontal: false, vertical: true)
      } else if let helper {
        Text(helper).font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .opacity(isEnabled ? 1 : 0.6)
  }

  @ViewBuilder private var field: some View {
    switch kind {
    case .text:
      TextField(placeholder, text: $text).textFieldStyle(.plain)
    case .secure:
      SecureField(placeholder, text: $text).textFieldStyle(.plain)
    case .multiline:
      TextField(placeholder, text: $text, axis: .vertical).textFieldStyle(.plain).lineLimit(3...6)
    }
  }

  private var borderColor: Color {
    if error != nil { return HP.Color.danger }
    return focused ? HP.Color.focusRing : HP.Color.border
  }
}
