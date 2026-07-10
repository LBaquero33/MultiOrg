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
    List {
      Section {
        Picker("Chat type", selection: $mode) {
          ForEach(Mode.allCases) { m in
            Text(m.rawValue).tag(m)
          }
        }
        .pickerStyle(.segmented)

        TextField("Search users", text: $query)
          .textFieldStyle(.roundedBorder)

        if mode == .group {
          TextField("Group name (optional)", text: $groupTitle)
            .textFieldStyle(.roundedBorder)
        }
      }

      if isLoading {
        Section {
          HStack(spacing: 10) { ProgressView(); Text("Loading…").foregroundStyle(.secondary) }
        }
      } else {
        Section("Users") {
          ForEach(filteredProfiles) { p in
            Button {
              toggle(p.id)
            } label: {
              HStack(spacing: 12) {
                DHDAvatarView(
                  url: {
                    guard let path = p.avatar_path else { return nil }
                    return appState.supabase?.publicAvatarURL(path: path)
                  }(),
                  initials: String(p.displayName.prefix(2)).uppercased(),
                  size: 30
                )
                VStack(alignment: .leading, spacing: 1) {
                  Text(p.displayName).font(.headline)
                  Text("\(p.role.capitalized) • \(p.shortId)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: selected.contains(p.id) ? "checkmark.circle.fill" : "circle")
                  .foregroundStyle(selected.contains(p.id) ? DHDTheme.accent : .secondary)
              }
              .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
    .navigationTitle("New Chat")
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") { dismiss() }
      }
      ToolbarItem(placement: .primaryAction) {
        Button {
          Task { await create() }
        } label: {
          if isSaving { ProgressView() } else { Text("Create") }
        }
        .disabled(!canCreate || isSaving)
      }
    }
    .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { _ in errorText = nil })) {
      Button("OK", role: .cancel) {}
    } message: { Text(errorText ?? "") }
    .task { await loadUsers() }
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
