import SwiftUI

/// Modal surface chrome — title, optional close, content. Presented as a sheet
/// on iOS or a click-out floating panel on macOS via `hpModal`. In previews the
/// surface is shown inline.
struct HPModalContainer<Content: View>: View {
  let title: String
  var onClose: (() -> Void)? = nil
  let content: () -> Content

  init(title: String, onClose: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> Content) {
    self.title = title
    self.onClose = onClose
    self.content = content
  }

  var body: some View {
    VStack(alignment: .leading, spacing: HP.Space.md) {
      HStack {
        Text(title).font(HP.Font.title).tracking(HP.Font.titleTracking).foregroundStyle(HP.Color.text)
          .fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: HP.Space.sm)
        if let onClose {
          Button { onClose() } label: {
            Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(HP.Color.textMuted)
          }
          .buttonStyle(.plain)
          .frame(width: 44, height: 44)
          .contentShape(Rectangle())
          .accessibilityLabel("Close")
        }
      }
      content()
    }
    .padding(HP.Space.lg)
    .frame(maxWidth: 520)
    .background(RoundedRectangle(cornerRadius: HP.Radius.xl, style: .continuous).fill(HP.Color.surface))
    .overlay(
      RoundedRectangle(cornerRadius: HP.Radius.xl, style: .continuous)
        .strokeBorder(HP.Color.borderStrong, lineWidth: 1)
        .allowsHitTesting(false)
    )
    .hpShadow(HP.Shadow.modal)
  }
}

/// Confirmation dialog built on the modal surface. Destructive confirms use the
/// danger button.
struct HPConfirmationDialog: View {
  let title: String
  let message: String
  var confirmTitle: String = "Confirm"
  var destructive: Bool = false
  var onConfirm: () -> Void = {}
  var onCancel: () -> Void = {}

  @Environment(\.dynamicTypeSize) private var dts

  var body: some View {
    HPModalContainer(title: title) {
      VStack(alignment: .leading, spacing: HP.Space.md) {
        Text(message).font(HP.Font.body).foregroundStyle(HP.Color.textMuted)
          .fixedSize(horizontal: false, vertical: true)
        actions
      }
    }
  }

  @ViewBuilder private var actions: some View {
    let confirm = HPButton(title: confirmTitle, variant: destructive ? .destructive : .primary,
                           size: .lg, fullWidth: dts.isAccessibilitySize, action: onConfirm)
    let cancel = HPButton(title: "Cancel", variant: .secondary,
                          size: .lg, fullWidth: dts.isAccessibilitySize, action: onCancel)
    if dts.isAccessibilitySize {
      // Full-width, stacked, complete labels — destructive/primary on top.
      VStack(spacing: HP.Space.sm) { confirm; cancel }
    } else {
      HStack(spacing: HP.Space.sm) { Spacer(minLength: 0); cancel; confirm }
    }
  }
}

extension View {
  /// Presents modal content over a scrim; tapping the scrim dismisses.
  func hpModal<C: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> C) -> some View {
    modifier(HPModalPresenter(isPresented: isPresented, modalContent: content))
  }
}

private struct HPModalPresenter<C: View>: ViewModifier {
  @Binding var isPresented: Bool
  @ViewBuilder let modalContent: () -> C
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func body(content: Content) -> some View {
    content.overlay {
      if isPresented {
        ZStack {
          Color.black.opacity(0.55).ignoresSafeArea()
            .onTapGesture { isPresented = false }
          modalContent()
            .padding(HP.Space.lg)
        }
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
        #if os(macOS)
        .onExitCommand { isPresented = false }
        #endif
      }
    }
    .animation(reduceMotion ? HP.Motion.quick : HP.Motion.emphasis, value: isPresented)
  }
}
