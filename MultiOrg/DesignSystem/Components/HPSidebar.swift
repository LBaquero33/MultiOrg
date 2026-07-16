import SwiftUI

/// Desktop/iPad navigation sidebar: org identity header + grouped, role- and
/// entitlement-aware destinations. Locked destinations are disabled with a lock;
/// preview destinations are badged. Uses local mock config only. Evolves from
/// `CoachRootView`'s `NavigationSplitView`.
struct HPSidebar: View {
  let orgIdentity: HPIdentity
  let role: HPRole
  let groups: [HPNavGroup]
  @Binding var selection: UUID?

  @Environment(\.dynamicTypeSize) private var dts

  var body: some View {
    VStack(alignment: .leading, spacing: HP.Space.md) {
      header
      ForEach(groups) { group in
        VStack(alignment: .leading, spacing: 2) {
          if let title = group.title {
            Text(title.uppercased())
              .font(HP.Font.eyebrow).tracking(HP.Font.eyebrowTracking)
              .foregroundStyle(HP.Color.textMuted)
              .padding(.horizontal, HP.Space.sm)
              .padding(.top, HP.Space.xs)
          }
          ForEach(group.items) { item in row(item) }
        }
      }
      Spacer(minLength: 0)
    }
    .padding(HP.Space.sm)
    .frame(maxWidth: 280, maxHeight: .infinity, alignment: .top)
    .background(HP.Color.surface)
    .overlay(alignment: .trailing) { Rectangle().fill(HP.Color.border).frame(width: 1) }
  }

  private var header: some View {
    HStack(spacing: HP.Space.sm) {
      RoundedRectangle(cornerRadius: HP.Radius.sm, style: .continuous)
        .fill(orgIdentity.gradient)
        .frame(width: 34, height: 34)
        .overlay(Image(systemName: "diamond.fill").font(.caption).foregroundStyle(.white.opacity(0.92)))
      VStack(alignment: .leading, spacing: 0) {
        Text(orgIdentity.shortName).font(HP.Font.headline).foregroundStyle(HP.Color.text).lineLimit(1)
        Text(role.rawValue).font(HP.Font.caption).foregroundStyle(HP.Color.textMuted).lineLimit(1)
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, HP.Space.xs)
    .padding(.vertical, HP.Space.xs)
    .accessibilityElement(children: .combine)
  }

  @ViewBuilder private func row(_ item: HPWorkspaceItem) -> some View {
    let selected = selection == item.id
    let accessibility = dts.isAccessibilitySize
    Button {
      if !item.locked { selection = item.id }
    } label: {
      HStack(alignment: .firstTextBaseline, spacing: HP.Space.sm) {
        // Fixed icon size (does not scale with Dynamic Type) so a large-text
        // row can't overflow the icon into the label.
        Image(systemName: item.icon).font(.system(size: 16)).frame(width: 24)
          .foregroundStyle(selected ? HP.Color.accent : HP.Color.textTertiary)
        // At accessibility sizes the label wraps and any badge/lock moves to a
        // second line so nothing overlaps.
        VStack(alignment: .leading, spacing: 6) {
          Text(item.title)
            .font(HP.Font.callout)
            .foregroundStyle(selected ? HP.Color.text : HP.Color.textTertiary)
            .lineLimit(accessibility ? 3 : 1)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
          if accessibility { statusMark(item) }
        }
        if !accessibility {
          Spacer(minLength: HP.Space.xs)
          statusMark(item)
        }
      }
      .padding(.horizontal, HP.Space.sm)
      .padding(.vertical, 8)
      .background(RoundedRectangle(cornerRadius: HP.Radius.sm, style: .continuous)
        .fill(selected ? HP.Color.accent.opacity(0.14) : .clear))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(item.locked)
    .opacity(item.locked ? 0.55 : 1)
    .accessibilityLabel(item.title)
    .accessibilityValue(item.locked ? "Locked" : (item.preview ? "Preview" : ""))
    .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
  }

  @ViewBuilder private func statusMark(_ item: HPWorkspaceItem) -> some View {
    if item.locked {
      Image(systemName: "lock.fill").font(.caption2).foregroundStyle(HP.Color.textMuted)
    } else if item.preview {
      HPStatusBadge(text: "Preview", kind: .gold)
    }
  }
}
