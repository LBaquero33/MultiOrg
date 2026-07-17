import SwiftUI

/// Role label used by the shared Home Plate navigation chrome.
enum HPRole: String, CaseIterable, Identifiable {
  case player = "Player"
  case parent = "Parent"
  case coach = "Coach"
  case owner = "Owner/Admin"
  case platformAdmin = "Platform Admin"

  var id: String { rawValue }
}

/// Presentation metadata for one workspace destination.
///
/// `id` preserves the original preview and UUID-selection API. Production
/// navigation supplies a deterministic `key` and selects through
/// `HPSidebar.init(...selectionKey:)`, so rebuilding a role inventory does not
/// lose its selection.
struct HPWorkspaceItem: Identifiable, Hashable {
  let id: UUID
  let key: String
  let title: String
  let icon: String
  var locked: Bool
  var preview: Bool

  init(
    id: UUID = UUID(),
    key: String? = nil,
    title: String,
    icon: String,
    locked: Bool = false,
    preview: Bool = false
  ) {
    self.id = id
    self.key = key ?? id.uuidString.lowercased()
    self.title = title
    self.icon = icon
    self.locked = locked
    self.preview = preview
  }
}

/// A stable presentation group for sidebar and workspace-directory items.
struct HPNavGroup: Identifiable {
  let id: UUID
  let key: String
  let title: String?
  let items: [HPWorkspaceItem]

  init(
    id: UUID = UUID(),
    key: String? = nil,
    title: String?,
    items: [HPWorkspaceItem]
  ) {
    self.id = id
    self.key = key ?? ([title ?? "primary"] + items.map(\.key)).joined(separator: ":")
    self.title = title
    self.items = items
  }
}

/// Desktop/iPad navigation sidebar: org identity header + grouped, role- and
/// entitlement-aware destinations. Locked destinations are disabled with a lock;
/// preview destinations are badged. Evolves from `CoachRootView`'s
/// `NavigationSplitView`.
struct HPSidebar: View {
  let orgIdentity: HPIdentity
  let role: HPRole
  let groups: [HPNavGroup]

  private enum SelectionBinding {
    case id(Binding<UUID?>)
    case key(Binding<String?>)
  }

  private let selectionBinding: SelectionBinding

  @Environment(\.dynamicTypeSize) private var dts

  /// Backward-compatible preview initializer.
  init(
    orgIdentity: HPIdentity,
    role: HPRole,
    groups: [HPNavGroup],
    selection: Binding<UUID?>
  ) {
    self.orgIdentity = orgIdentity
    self.role = role
    self.groups = groups
    selectionBinding = .id(selection)
  }

  /// Production initializer using the caller's deterministic destination key.
  init(
    orgIdentity: HPIdentity,
    role: HPRole,
    groups: [HPNavGroup],
    selectionKey: Binding<String?>
  ) {
    self.orgIdentity = orgIdentity
    self.role = role
    self.groups = groups
    selectionBinding = .key(selectionKey)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: HP.Space.md) {
      header
      ScrollView {
        LazyVStack(alignment: .leading, spacing: HP.Space.md) {
          ForEach(groups, id: \.key) { group in
            VStack(alignment: .leading, spacing: 2) {
              if let title = group.title {
                Text(title.uppercased())
                  .font(HP.Font.eyebrow).tracking(HP.Font.eyebrowTracking)
                  .foregroundStyle(HP.Color.textMuted)
                  .padding(.horizontal, HP.Space.sm)
                  .padding(.top, HP.Space.xs)
              }
              ForEach(group.items, id: \.key) { item in row(item) }
            }
          }
        }
      }
    }
    .padding(HP.Space.sm)
    .frame(
      maxWidth: dts.isAccessibilitySize ? 360 : 280,
      maxHeight: .infinity,
      alignment: .top
    )
    .background(HP.Color.surface)
    .overlay(alignment: .trailing) { Rectangle().fill(HP.Color.border).frame(width: 1) }
  }

  private var header: some View {
    Group {
      if dts.isAccessibilitySize {
        ViewThatFits(in: .horizontal) {
          HStack(alignment: .top, spacing: HP.Space.sm) {
            identityMark
            identityLabels(lineLimit: 1)
          }
          .fixedSize(horizontal: true, vertical: false)

          VStack(alignment: .leading, spacing: HP.Space.sm) {
            identityMark
            identityLabels(lineLimit: nil)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      } else {
        HStack(spacing: HP.Space.sm) {
          identityMark
          identityLabels(lineLimit: 1)
          Spacer(minLength: 0)
        }
      }
    }
    .padding(.horizontal, HP.Space.xs)
    .padding(.vertical, HP.Space.xs)
    .accessibilityElement(children: .combine)
  }

  private var identityMark: some View {
    RoundedRectangle(cornerRadius: HP.Radius.sm, style: .continuous)
      .fill(orgIdentity.gradient)
      .frame(width: 34, height: 34)
      .overlay(
        Image(systemName: "diamond.fill")
          .font(.caption)
          .foregroundStyle(DHDTheme.identityText.opacity(0.92))
      )
      .accessibilityHidden(true)
  }

  private func identityLabels(lineLimit: Int?) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(orgIdentity.shortName)
        .font(HP.Font.headline)
        .foregroundStyle(HP.Color.text)
        .lineLimit(lineLimit)
        .fixedSize(horizontal: false, vertical: true)
      Text(role.rawValue)
        .font(HP.Font.caption)
        .foregroundStyle(HP.Color.textMuted)
        .lineLimit(lineLimit)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  @ViewBuilder private func row(_ item: HPWorkspaceItem) -> some View {
    let selected = isSelected(item)
    let accessibility = dts.isAccessibilitySize
    Button {
      if !item.locked { select(item) }
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
            .lineLimit(accessibility ? nil : 1)
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
      .frame(minHeight: DHDTheme.minimumTouchTarget)
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

  private func isSelected(_ item: HPWorkspaceItem) -> Bool {
    switch selectionBinding {
    case .id(let selection): selection.wrappedValue == item.id
    case .key(let selection): selection.wrappedValue == item.key
    }
  }

  private func select(_ item: HPWorkspaceItem) {
    switch selectionBinding {
    case .id(let selection): selection.wrappedValue = item.id
    case .key(let selection): selection.wrappedValue = item.key
    }
  }

  @ViewBuilder private func statusMark(_ item: HPWorkspaceItem) -> some View {
    if item.locked {
      Image(systemName: "lock.fill").font(.caption2).foregroundStyle(HP.Color.textMuted)
    } else if item.preview {
      HPStatusBadge(text: "Preview", kind: .gold)
    }
  }
}
