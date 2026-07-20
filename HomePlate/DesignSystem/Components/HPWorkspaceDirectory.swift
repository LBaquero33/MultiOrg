import SwiftUI

/// Branded iPhone "More" replacement: a grid of workspace tiles, role- and
/// entitlement-gated (locked / preview). Adaptive grid that collapses to one
/// column at accessibility sizes.
struct HPWorkspaceDirectory: View {
  let groups: [HPNavGroup]
  var onSelect: (HPWorkspaceItem) -> Void = { _ in }

  @Environment(\.dynamicTypeSize) private var dts

  private var columns: [GridItem] {
    dts.isAccessibilitySize
      ? [GridItem(.flexible(), spacing: HP.Space.sm)]
      : [GridItem(.adaptive(minimum: 150), spacing: HP.Space.sm)]
  }

  private var items: [HPWorkspaceItem] { groups.flatMap(\.items) }

  var body: some View {
    LazyVGrid(columns: columns, spacing: HP.Space.sm) {
      ForEach(items, id: \.key) { item in
        Button { if !item.locked { onSelect(item) } } label: { tile(item) }
          .buttonStyle(.plain)
          .disabled(item.locked)
          .accessibilityLabel(item.title)
          .accessibilityValue(item.locked ? "Locked" : (item.preview ? "Preview" : ""))
      }
    }
  }

  private func tile(_ item: HPWorkspaceItem) -> some View {
    VStack(alignment: .leading, spacing: HP.Space.xs) {
      HStack {
        Image(systemName: item.icon).font(.title3)
          .foregroundStyle(item.locked ? HP.Color.textMuted : HP.Color.accent)
        Spacer(minLength: HP.Space.xs)
        if item.locked {
          Image(systemName: "lock.fill").font(.caption).foregroundStyle(HP.Color.textMuted)
        } else if item.preview {
          HPStatusBadge(text: "Preview", kind: .gold)
        }
      }
      Text(item.title)
        .font(HP.Font.headline).foregroundStyle(HP.Color.text)
        .lineLimit(3).fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(HP.Space.md)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: HP.Radius.lg, style: .continuous).fill(HP.Color.surface))
    .overlay(RoundedRectangle(cornerRadius: HP.Radius.lg, style: .continuous).strokeBorder(HP.Color.border, lineWidth: 1))
    .opacity(item.locked ? 0.6 : 1)
    .contentShape(Rectangle())
  }
}
