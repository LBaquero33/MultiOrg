import SwiftUI

/// Removable filter pill. Active pills use a gold outline; inactive are muted.
struct HPDataPill: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  let label: String
  var isActive: Bool = false
  var showsRemoveIndicator: Bool = false
  var onRemove: (() -> Void)? = nil

  @ViewBuilder
  var body: some View {
    if let onRemove {
      Button(action: onRemove) { pillContent }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove \(label)")
    } else {
      pillContent
    }
  }

  private var pillContent: some View {
    HStack(spacing: 4) {
      Text(label)
        .font(HP.Font.caption.weight(.semibold))
        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
      if isActive, showsRemoveIndicator || onRemove != nil {
        Image(systemName: "xmark").font(.caption2)
          .accessibilityHidden(true)
      }
    }
    .padding(.horizontal, HP.Space.sm)
    .padding(.vertical, 6)
    .frame(minHeight: 44)
    .background(Capsule().fill(isActive ? HP.Color.accent.opacity(0.18) : HP.Color.surfaceRaised))
    .overlay(Capsule().strokeBorder(isActive ? HP.Color.accent.opacity(0.6) : HP.Color.border, lineWidth: 1))
    .foregroundStyle(isActive ? HP.Color.accent : HP.Color.textTertiary)
    .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: true)
  }
}

/// Horizontally scrolling filter bar of toggleable pills.
struct HPFilterBar: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  let pills: [String]
  @Binding var active: Set<String>

  var body: some View {
    Group {
      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: HP.Space.xs) {
          pillButtons
        }
      } else {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: HP.Space.sm) {
            pillButtons
          }
          .padding(.horizontal, 2)
          .padding(.vertical, 2)
        }
      }
    }
  }

  @ViewBuilder
  private var pillButtons: some View {
    ForEach(pills, id: \.self) { pill in
      Button {
        if active.contains(pill) { active.remove(pill) } else { active.insert(pill) }
      } label: {
        HPDataPill(
          label: pill,
          isActive: active.contains(pill),
          showsRemoveIndicator: active.contains(pill)
        )
      }
      .buttonStyle(.plain)
      .frame(minHeight: 44, alignment: .leading)
      .accessibilityLabel("\(active.contains(pill) ? "Remove" : "Add") \(pill) filter")
      .accessibilityAddTraits(active.contains(pill) ? .isSelected : [])
    }
  }
}
