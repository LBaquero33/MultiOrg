import SwiftUI

/// Parent-facing home:
/// - Accept invites
/// - View linked children (read-only performance data)
/// - Book facilities + request payment on behalf
struct ParentHomeView: View {
  @EnvironmentObject private var appState: AppState

  @State private var invites: [SDParentInvite] = []
  @State private var links: [SDParentChildLink] = []
  @State private var children: [Profile] = []

  @State private var isLoading = false
  @State private var errorText: String?

#if os(macOS)
  private enum SidebarSelection: Hashable {
    case account
    case child(UUID)

    var storageValue: String {
      switch self {
      case .account: return "account"
      case .child(let id): return "child:\(id.uuidString)"
      }
    }

    init?(storageValue: String) {
      let raw = storageValue.trimmingCharacters(in: .whitespacesAndNewlines)
      if raw == "account" { self = .account; return }
      if raw.hasPrefix("child:") {
        let idRaw = String(raw.dropFirst("child:".count))
        if let id = UUID(uuidString: idRaw) {
          self = .child(id)
          return
        }
      }
      return nil
    }
  }

  @SceneStorage("parent.sidebarSelection") private var selectionStorage: String = ""
  @State private var selection: SidebarSelection? = nil
#endif

  var body: some View {
    Group {
#if os(macOS)
      NavigationSplitView {
        childList
          .navigationTitle("Children")
      } detail: {
        switch selection ?? .account {
        case .account:
          AccountView()
            .environmentObject(appState)
        case .child(let id):
          if let child = children.first(where: { $0.id == id }) {
            ParentChildProfileView(child: child)
              .environmentObject(appState)
          } else {
            emptyState
          }
        }
      }
      .task { await reload() }
#else
      NavigationStack {
        List {
          if isLoading {
            HStack(spacing: 10) { ProgressView(); Text("Loading…").foregroundStyle(.secondary) }
          }
          if children.isEmpty, !isLoading {
            Text("No children linked yet.")
              .foregroundStyle(.secondary)
          } else {
            Section("Children") {
              ForEach(children) { c in
                NavigationLink {
                  ParentChildProfileView(child: c)
                    .environmentObject(appState)
                } label: {
                HStack(spacing: 12) {
                  DHDAvatarView(
                    url: {
                      guard let path = c.avatar_path else { return nil }
                      return appState.supabase?.publicAvatarURL(path: path)
                    }(),
                    initials: String(c.displayName.prefix(2)).uppercased(),
                    size: 36
                  )
                  VStack(alignment: .leading, spacing: 2) {
                    Text(c.displayName).font(.headline)
                    Text(c.shortId).font(.caption).foregroundStyle(.secondary)
                  }
                  }
                  .padding(.vertical, 4)
                }
              }
            }
          }
          Section {
            Button {
              Task { await reload() }
            } label: {
              Label("Refresh", systemImage: "arrow.clockwise")
            }
            Button(role: .destructive) {
              Task { await appState.signOut() }
            } label: {
              Text("Sign Out")
            }
          }
        }
        .navigationTitle("Parent")
        .task { await reload() }
      }
#endif
    }
    .sheet(isPresented: Binding(get: { !invites.isEmpty }, set: { _ in })) {
      ParentInviteAcceptanceSheet(invites: $invites, onAccept: { inviteId in
        Task { await accept(inviteId: inviteId) }
      })
      .environmentObject(appState)
    }
    .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { _ in errorText = nil })) {
      Button("OK", role: .cancel) {}
    } message: { Text(errorText ?? "") }
  }

#if os(macOS)
  private var childList: some View {
    List(selection: $selection) {
      if isLoading {
        HStack(spacing: 10) { ProgressView(); Text("Loading…").foregroundStyle(.secondary) }
      }
      Section {
        Label("Account", systemImage: "gearshape")
          .tag(SidebarSelection.account)
      }
      ForEach(children) { c in
        Text(c.displayName)
          .tag(SidebarSelection.child(c.id))
      }
    }
    .onChange(of: selection) { _, newValue in
      selectionStorage = newValue?.storageValue ?? ""
    }
    .toolbar {
      ToolbarItemGroup(placement: .automatic) {
        Button {
          Task { await reload() }
        } label: {
          Image(systemName: "arrow.clockwise")
        }
      }
    }
  }

  private var emptyState: some View {
    VStack(spacing: 10) {
      Text("Select a child")
        .font(.title3.weight(.semibold))
      Text("Choose a child to view their progress.")
        .foregroundStyle(DHDTheme.textSecondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(DHDTheme.pageBackground)
  }
#endif

  private func reload() async {
    guard let supabase = appState.supabase else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      invites = try await supabase.listMyParentInvites()
      links = try await supabase.listMyParentChildLinks()
      let ids = links.map(\.child_id)
      let profiles = try await supabase.listProfiles(ids: ids)
      // Only show player children.
      children = profiles.filter(\.isPlayer).sorted { $0.displayName < $1.displayName }

#if os(macOS)
      if let parsed = SidebarSelection(storageValue: selectionStorage) {
        selection = parsed
      }
      if case .child(let id) = selection, !children.contains(where: { $0.id == id }) {
        selection = nil
      }
      if selection == nil {
        selection = children.first.map { SidebarSelection.child($0.id) } ?? .account
      }
      selectionStorage = selection?.storageValue ?? ""
#endif
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func accept(inviteId: UUID) async {
    guard let supabase = appState.supabase else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      try await supabase.acceptParentInvite(inviteId: inviteId)
      await reload()
    } catch {
      errorText = error.localizedDescription
    }
  }
}

private struct ParentInviteAcceptanceSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Binding var invites: [SDParentInvite]
  let onAccept: (UUID) -> Void

  var body: some View {
    NavigationStack {
      List {
        Section {
          Text("You have been invited to view one or more players as a parent/guardian.")
            .foregroundStyle(.secondary)
        }
        Section("Invites") {
          ForEach(invites) { inv in
            HStack {
              VStack(alignment: .leading, spacing: 4) {
                Text("Player: \(inv.child_id.uuidString.prefix(6).uppercased())")
                  .font(.headline)
                if let rel = inv.relationship, !rel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                  Text(rel).font(.caption).foregroundStyle(.secondary)
                }
              }
              Spacer()
              Button("Accept") {
                onAccept(inv.id)
              }
              .buttonStyle(.borderedProminent)
            }
            .padding(.vertical, 4)
          }
        }
      }
      .navigationTitle("Parent invites")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Close") { dismiss() }
        }
      }
    }
  }
}
