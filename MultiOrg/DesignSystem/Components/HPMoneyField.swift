import SwiftUI

/// Presentation-only money entry. The authoritative value is **integer cents**;
/// no floating-point arithmetic is used for the monetary amount (parsing and
/// formatting are integer/string only). Currency handling here is purely for
/// display — backend remains authoritative for real money.
struct HPMoneyField: View {
  let label: String
  @Binding var cents: Int
  var currencyCode: String = "USD"
  var helper: String? = nil
  var error: String? = nil
  var isEnabled: Bool = true

  @FocusState private var focused: Bool
  @State private var digits: String = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(label.uppercased())
        .font(HP.Font.eyebrow).tracking(HP.Font.eyebrowTracking)
        .foregroundStyle(HP.Color.textMuted)

      HStack(spacing: 6) {
        Text(Self.symbol(currencyCode)).font(HP.Font.body).foregroundStyle(HP.Color.textMuted)
        TextField("0.00", text: $digits)
          .textFieldStyle(.plain)
          .font(HP.Font.number(.body))
          .foregroundStyle(HP.Color.text)
          #if os(iOS)
          .keyboardType(.numberPad)
          #endif
          .focused($focused)
          .disabled(!isEnabled)
          .onChange(of: digits) { _, newValue in
            cents = Self.centsFromDigits(newValue)
          }
        Spacer(minLength: 0)
        Text(Self.format(cents: cents, currencyCode: currencyCode))
          .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
          .lineLimit(1)
      }
      .padding(.horizontal, HP.Space.sm)
      .padding(.vertical, 10)
      .background(RoundedRectangle(cornerRadius: HP.Radius.md, style: .continuous).fill(HP.Color.input))
      .overlay(
        RoundedRectangle(cornerRadius: HP.Radius.md, style: .continuous)
          .strokeBorder(focused ? HP.Color.focusRing : (error != nil ? HP.Color.danger : HP.Color.border),
                        lineWidth: (focused || error != nil) ? 2 : 1)
      )

      if let error {
        Text(error).font(HP.Font.caption).foregroundStyle(HP.Color.danger)
      } else if let helper {
        Text(helper).font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
      }
    }
    .opacity(isEnabled ? 1 : 0.6)
    .onAppear { if digits.isEmpty && cents != 0 { digits = String(cents) } }
  }

  // MARK: - Integer-only helpers (no floating-point on the value)

  /// Interprets typed digits as an integer number of cents.
  static func centsFromDigits(_ string: String) -> Int {
    let onlyDigits = string.filter(\.isNumber).prefix(12)
    return Int(onlyDigits) ?? 0
  }

  /// Formats integer cents as `symbol whole.frac` using integer division only.
  static func format(cents: Int, currencyCode: String) -> String {
    let whole = cents / 100
    let frac = abs(cents % 100)
    let sign = cents < 0 ? "-" : ""
    let fracString = frac < 10 ? "0\(frac)" : "\(frac)"
    return "\(sign)\(symbol(currencyCode))\(abs(whole)).\(fracString)"
  }

  static func symbol(_ code: String) -> String {
    switch code.uppercased() {
    case "USD": "$"
    case "EUR": "€"
    case "GBP": "£"
    default: "$"
    }
  }
}
