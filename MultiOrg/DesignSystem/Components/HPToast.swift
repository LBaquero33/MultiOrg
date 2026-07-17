import Accessibility
import SwiftUI

/// Transient confirmation toast. Single implementation for the whole system
/// (replaces the duplicate inline toast in production later). Reduce-Motion
/// aware via the `hpToast` presenter.
struct HPToast: View {
  let text: String
  var systemImage: String? = "checkmark.circle.fill"
  var kind: HPStatusKind = .success

  var body: some View {
    HStack(spacing: HP.Space.xs) {
      if let systemImage {
        Image(systemName: systemImage).foregroundStyle(kind.color)
      }
      Text(text).font(HP.Font.callout).foregroundStyle(HP.Color.text)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.horizontal, HP.Space.md)
    .padding(.vertical, HP.Space.sm)
    .background(RoundedRectangle(cornerRadius: HP.Radius.md, style: .continuous).fill(HP.Color.surfaceRaised))
    .overlay(
      RoundedRectangle(cornerRadius: HP.Radius.md, style: .continuous)
        .strokeBorder(HP.Color.border, lineWidth: 1)
        .allowsHitTesting(false)
    )
    .hpShadow(HP.Shadow.modal)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Status: \(text)")
    .accessibilityAddTraits(.isStaticText)
    .onChange(of: text, initial: true) { _, value in
      AccessibilityNotification.Announcement("Status: \(value)").post()
    }
    .allowsHitTesting(false)
  }
}

extension View {
  /// Presents an `HPToast` from the top while `text` is non-nil.
  func hpToast(_ text: Binding<String?>) -> some View {
    modifier(HPToastModifier(text: text))
  }
}

private struct HPToastModifier: ViewModifier {
  @Binding var text: String?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func body(content: Content) -> some View {
    content.overlay(alignment: .top) {
      if let value = text {
        HPToast(text: value)
          .padding(.top, HP.Space.md)
          .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
      }
    }
    .animation(HP.Motion.quick, value: text)
    .task(id: text) {
      guard let presentedValue = text else { return }
      do {
        try await Task.sleep(for: .seconds(3))
      } catch {
        return
      }
      guard !Task.isCancelled, text == presentedValue else { return }
      text = nil
    }
  }
}
