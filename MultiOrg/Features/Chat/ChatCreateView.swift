import SwiftUI

struct ChatCreateView: View {
  @EnvironmentObject private var appState: AppState
  @Environment(\.dismiss) private var dismiss

  enum Mode: String, CaseIterable, Identifiable {
    case dm = "New DM"
    case group = "New Group"
    var id: String { rawValue }
  }

  let onCreated: (UUID) -> Void

  @State private var mode: Mode = .dm
  @State private var profiles: [Profile] = []
  @State private var query = ""
  @State private var groupTitle = ""
  @State private var selected: Set<UUID> = []

  @State private var isLoading = false
  @State private var errorText: String?
  @State private var isSaving = false

  private var myId: UUID? { appState.myProfile?.id }

  init(onCreated: @escaping (UUID) -> Void) {
    self.onCreated = onCreated
  }

  var body: some View {
    HPFormScreenLayout { _ in
      HPWorkspaceHeader(
        "New chat",
        context: mode == .dm
          ? "Choose one person for a direct message."
          : "Choose at least two people for a group."
      )
    } sections: { context in
      VStack(alignment: .leading, spacing: HP.Space.md) {
        HPCard(style: .flat) {
          VStack(alignment: .leading, spacing: HP.Space.md) {
            Text("CHAT TYPE")
              .font(HP.Font.eyebrow)
              .tracking(HP.Font.eyebrowTracking)
              .foregroundStyle(HP.Color.textMuted)
            HPSegmentedControl(
              options: Mode.allCases.map { (value: $0, label: $0.rawValue) },
              selection: $mode
            )

            HPSearchBar(text: $query, placeholder: "Search users")

            if mode == .group {
              HPFormField(
                label: "Group name (optional)",
                text: $groupTitle,
                placeholder: "e.g. 14U coaches"
              )
            }
          }
        }

        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            HPSectionHeader("Users") {
              HPStatusBadge(
                text: "\(selected.count) selected",
                kind: selected.isEmpty ? .neutral : .gold
              )
            }

            if isLoading {
              HPLoadingState(text: "Loading users…")
            } else if filteredProfiles.isEmpty {
              HPEmptyState(
                title: query.isEmpty ? "No users available" : "No users match",
                message: query.isEmpty
                  ? "There are no eligible people for this chat."
                  : "Try a different name or Home Plate ID.",
                systemImage: "person.2"
              )
            } else {
              LazyVStack(alignment: .leading, spacing: HP.Space.xs) {
                ForEach(filteredProfiles) { profile in
                  profileSelectionRow(profile, stacksVertically: context.isAccessibilitySize)
                }
              }
            }
          }
        }
      }
    } primaryAction: { context in
      HPButton(
        title: "Create chat",
        systemImage: "bubble.left.and.bubble.right",
        variant: .primary,
        size: .lg,
        isLoading: isSaving,
        fullWidth: context.isAccessibilitySize
      ) {
        Task { await create() }
      }
      .disabled(!canCreate || isSaving)
    } secondaryAction: { _ in
      EmptyView()
    }
    .navigationTitle("New Chat")
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") { dismiss() }
          #if os(macOS)
          .keyboardShortcut(.cancelAction)
          #endif
      }
    }
    .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { _ in errorText = nil })) {
      Button("OK", role: .cancel) {}
    } message: { Text(errorText ?? "") }
    .task { await loadUsers() }
  }

  private func profileSelectionRow(
    _ profile: Profile,
    stacksVertically: Bool
  ) -> some View {
    let isSelected = selected.contains(profile.id)

    return Button {
      toggle(profile.id)
    } label: {
      let layout = stacksVertically
        ? AnyLayout(VStackLayout(alignment: .leading, spacing: HP.Space.xs))
        : AnyLayout(HStackLayout(alignment: .top, spacing: HP.Space.sm))
      layout {
        profileIdentity(profile)
        if !stacksVertically {
          Spacer(minLength: HP.Space.sm)
        }
        selectionIndicator(isSelected)
      }
      .padding(HP.Space.sm)
      .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: HP.Radius.md, style: .continuous)
          .fill(isSelected ? HP.Color.accent.opacity(0.10) : HP.Color.surface)
      )
      .overlay(
        RoundedRectangle(cornerRadius: HP.Radius.md, style: .continuous)
          .strokeBorder(isSelected ? HP.Color.borderStrong : HP.Color.border, lineWidth: 1)
          .allowsHitTesting(false)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("\(profile.displayName), \(profile.role.capitalized), \(profile.shortId)")
    .accessibilityValue(isSelected ? "Selected" : "Not selected")
    .accessibilityHint(isSelected ? "Removes this person" : "Adds this person")
  }

  private func profileIdentity(_ profile: Profile) -> some View {
    HStack(alignment: .top, spacing: HP.Space.sm) {
      DHDAvatarView(
        url: {
          guard let path = profile.avatar_path else { return nil }
          return appState.supabase?.publicAvatarURL(path: path)
        }(),
        initials: String(profile.displayName.prefix(2)).uppercased(),
        size: 32
      )
      VStack(alignment: .leading, spacing: 2) {
        Text(profile.displayName)
          .font(HP.Font.headline)
          .foregroundStyle(HP.Color.text)
          .fixedSize(horizontal: false, vertical: true)
        Text("\(profile.role.capitalized) • \(profile.shortId)")
          .font(HP.Font.caption)
          .foregroundStyle(HP.Color.textMuted)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  @ViewBuilder
  private func selectionIndicator(_ isSelected: Bool) -> some View {
    if isSelected {
      HPStatusBadge(text: "Selected", kind: .gold)
    } else {
      Label("Not selected", systemImage: "circle")
        .font(HP.Font.caption)
        .foregroundStyle(HP.Color.textMuted)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var filteredProfiles: [Profile] {
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let base = profiles.filter { $0.id != myId }
    guard !q.isEmpty else { return base }
    return base.filter { p in
      p.displayName.lowercased().contains(q) || p.shortId.lowercased().contains(q)
    }
  }

  private var canCreate: Bool {
    switch mode {
    case .dm: return selected.count == 1
    case .group: return selected.count >= 2
    }
  }

  private func toggle(_ id: UUID) {
    switch mode {
    case .dm:
      if selected.contains(id) {
        selected.remove(id)
      } else {
        selected = [id]
      }
    case .group:
      if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }
  }

  private func loadUsers() async {
    guard let supabase = appState.supabase else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      // Coach: can DM anyone (players/parents/coaches) for admin workflows.
      // Player/Parent: only list coaches (RLS allows select where role='coach').
      if (appState.myProfile?.role.lowercased() ?? "") == "coach" {
        profiles = try await supabase.listAllProfilesForDirectory()
      } else {
        profiles = try await supabase.listCoachProfilesForDirectory()
      }
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func create() async {
    guard let supabase = appState.supabase else { return }
    isSaving = true
    defer { isSaving = false }
    do {
      let channelId: UUID
      switch mode {
      case .dm:
        guard let other = selected.first else { return }
        channelId = try await supabase.getOrCreateDM(otherUserId: other, orgId: appState.activeOrgId)
      case .group:
        channelId = try await supabase.createGroup(title: groupTitle, memberIds: Array(selected), orgId: appState.activeOrgId)
      }
      onCreated(channelId)
      dismiss()
    } catch {
      errorText = error.localizedDescription
    }
  }
}
