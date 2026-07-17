import SwiftUI

/// Search field with leading magnifier, clear button, and a visible gold focus
/// ring. Debounce/filtering is the caller's concern (presentation only).
struct HPSearchBar: View {
  @Binding var text: String
  var placeholder: String = "Search"
  @FocusState private var focused: Bool

  var body: some View {
    HStack(spacing: HP.Space.xs) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(HP.Color.textMuted)
        .accessibilityHidden(true)
      TextField(placeholder, text: $text)
        .textFieldStyle(.plain)
        .font(HP.Font.body)
        .foregroundStyle(HP.Color.text)
        .frame(minHeight: 44)
        .focused($focused)
      if !text.isEmpty {
        Button { text = "" } label: {
          Image(systemName: "xmark.circle.fill").foregroundStyle(HP.Color.textMuted)
        }
        .buttonStyle(.plain)
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .accessibilityLabel("Clear search")
      }
    }
    .padding(.horizontal, HP.Space.sm)
    .frame(minHeight: 44)
    .background(RoundedRectangle(cornerRadius: HP.Radius.md, style: .continuous).fill(HP.Color.input))
    .overlay(
      RoundedRectangle(cornerRadius: HP.Radius.md, style: .continuous)
        .strokeBorder(focused ? HP.Color.focusRing : HP.Color.border, lineWidth: focused ? 2 : 1)
        .allowsHitTesting(false)
    )
  }
}
