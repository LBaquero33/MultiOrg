import SwiftUI

/// Removable filter pill. Active pills use a gold outline; inactive are muted.
struct HPDataPill: View {
  let label: String
  var isActive: Bool = false
  var onRemove: (() -> Void)? = nil

  var body: some View {
    HStack(spacing: 4) {
      Text(label).font(HP.Font.caption.weight(.semibold)).lineLimit(1)
      if isActive, let onRemove {
        Button { onRemove() } label: {
          Image(systemName: "xmark").font(.caption2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove \(label)")
      }
    }
    .padding(.horizontal, HP.Space.sm)
    .padding(.vertical, 6)
    .background(Capsule().fill(isActive ? HP.Color.accent.opacity(0.18) : HP.Color.surfaceRaised))
    .overlay(Capsule().strokeBorder(isActive ? HP.Color.accent.opacity(0.6) : HP.Color.border, lineWidth: 1))
    .foregroundStyle(isActive ? HP.Color.accent : HP.Color.textTertiary)
    .fixedSize()
  }
}

/// Horizontally scrolling filter bar of toggleable pills.
struct HPFilterBar: View {
  let pills: [String]
  @Binding var active: Set<String>

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: HP.Space.sm) {
        ForEach(pills, id: \.self) { pill in
          HPDataPill(
            label: pill,
            isActive: active.contains(pill),
            onRemove: active.contains(pill) ? { active.remove(pill) } : nil
          )
          .onTapGesture {
            if active.contains(pill) { active.remove(pill) } else { active.insert(pill) }
          }
        }
      }
      .padding(.horizontal, 2)
      .padding(.vertical, 2)
    }
  }
}
