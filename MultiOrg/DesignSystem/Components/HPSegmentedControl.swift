import SwiftUI

/// Styled segmented control with a gold selection indicator. Replaces the stock
/// segmented control. Keep to ≤4 segments; use a menu beyond that.
struct HPSegmentedControl<T: Hashable>: View {
  let options: [(value: T, label: String)]
  @Binding var selection: T
  @Namespace private var ns
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var dts

  var body: some View {
    // At accessibility sizes horizontal segments truncate long labels
    // (e.g. "Owner/Admin"), so switch to a vertical selection list.
    if dts.isAccessibilitySize { verticalList } else { horizontalSegments }
  }

  private var verticalList: some View {
    VStack(spacing: 4) {
      ForEach(options, id: \.value) { option in
        let isSelected = option.value == selection
        Button {
          if reduceMotion { selection = option.value }
          else { withAnimation(HP.Motion.quick) { selection = option.value } }
        } label: {
          HStack(spacing: HP.Space.sm) {
            Text(option.label)
              .font(HP.Font.callout.weight(.semibold))
              .fixedSize(horizontal: false, vertical: true)
              .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
              .foregroundStyle(isSelected ? HP.Color.accent : HP.Color.textMuted)
          }
          .padding(.horizontal, HP.Space.sm)
          .padding(.vertical, 10)
          .frame(minHeight: 44)
          .background(RoundedRectangle(cornerRadius: HP.Radius.sm, style: .continuous)
            .fill(isSelected ? HP.Color.accent.opacity(0.14) : .clear))
          .foregroundStyle(isSelected ? HP.Color.text : HP.Color.textTertiary)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.label)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
      }
    }
    .padding(4)
    .background(RoundedRectangle(cornerRadius: HP.Radius.md, style: .continuous).fill(HP.Color.surfaceRaised))
    .overlay(
      RoundedRectangle(cornerRadius: HP.Radius.md, style: .continuous)
        .strokeBorder(HP.Color.border, lineWidth: 1)
        .allowsHitTesting(false)
    )
  }

  private var horizontalSegments: some View {
    HStack(spacing: 4) {
      ForEach(options, id: \.value) { option in
        let isSelected = option.value == selection
        Button {
          if reduceMotion { selection = option.value }
          else { withAnimation(HP.Motion.quick) { selection = option.value } }
        } label: {
          Text(option.label)
            .font(HP.Font.callout.weight(.semibold))
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .frame(minHeight: 44)
            .background {
              if isSelected {
                RoundedRectangle(cornerRadius: HP.Radius.sm, style: .continuous)
                  .fill(HP.Color.accent)
                  .matchedGeometryEffect(id: "hp-seg", in: ns)
              }
            }
            .foregroundStyle(isSelected ? HP.Color.accentText : HP.Color.textTertiary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.label)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
      }
    }
    .padding(4)
    .background(RoundedRectangle(cornerRadius: HP.Radius.md, style: .continuous).fill(HP.Color.surfaceRaised))
    .overlay(
      RoundedRectangle(cornerRadius: HP.Radius.md, style: .continuous)
        .strokeBorder(HP.Color.border, lineWidth: 1)
        .allowsHitTesting(false)
    )
  }
}
