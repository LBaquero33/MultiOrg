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
      .task(id: appState.activeOrgId) { await reload() }
#else
      NavigationStack {
        HPWorkspaceScreenLayout {
          HPWorkspaceHeader(
            "Parent",
            context: "Linked player profiles"
          )
        } attention: {
          if isLoading {
            HPCard {
              HPLoadingState(text: "Loading linked children…")
            }
          }
        } metrics: {
          HPMetricCard(
            title: "Linked players",
            value: "\(children.count)",
            context: children.count == 1 ? "1 child profile" : "\(children.count) child profiles"
          )
        } supporting: {
          HPCard {
            VStack(alignment: .leading, spacing: HP.Space.sm) {
              HPSectionHeader("Children") {
                HPStatusBadge(text: "\(children.count)", kind: .neutral)
              }

              if children.isEmpty, !isLoading {
                HPEmptyState(
                  title: "No children linked yet",
                  message: "Accepted parent invitations will appear here.",
                  systemImage: "person.2"
                )
              } else {
                ForEach(children) { child in
                  NavigationLink {
                    ParentChildProfileView(child: child)
                      .environmentObject(appState)
                  } label: {
                    HStack(spacing: HP.Space.sm) {
                      DHDAvatarView(
                        url: {
                          guard let path = child.avatar_path else { return nil }
                          return appState.supabase?.publicAvatarURL(path: path)
                        }(),
                        initials: String(child.displayName.prefix(2)).uppercased(),
                        size: 36
                      )
                      VStack(alignment: .leading, spacing: 2) {
                        Text(child.displayName)
                          .font(HP.Font.headline)
                          .foregroundStyle(HP.Color.text)
                          .fixedSize(horizontal: false, vertical: true)
                        Text(child.shortId)
                          .font(HP.Font.caption)
                          .foregroundStyle(HP.Color.textMuted)
                      }
                      .frame(maxWidth: .infinity, alignment: .leading)
                      Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(HP.Color.textMuted)
                        .accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                  }
                  .buttonStyle(.plain)

                  if child.id != children.last?.id {
                    Divider().overlay(HP.Color.border.opacity(0.5))
                  }
                }
              }
            }
          }
        }
        .navigationTitle("Parent")
        .toolbar {
          ToolbarItem(placement: .topBarTrailing) {
            Menu {
              Button {
                Task { await reload() }
              } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
              }
              Button(role: .destructive) {
                Task { await appState.signOut() }
              } label: {
                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
              }
            } label: {
              Image(systemName: "ellipsis.circle")
            }
          }
        }
        .task(id: appState.activeOrgId) { await reload() }
      }
#endif
    }
    .sheet(
      isPresented: Binding(
        get: { !invites.isEmpty },
        set: { isPresented in
          if !isPresented { invites = [] }
        }
      )
    ) {
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
        HStack(spacing: HP.Space.sm) {
          ProgressView()
          Text("Loading…").foregroundStyle(HP.Color.textMuted)
        }
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
    HPStateScreenLayout { _ in
      HPCard {
        HPEmptyState(
          title: "Select a child",
          message: "Choose a child to view their progress.",
          systemImage: "person.crop.circle"
        )
      }
    }
  }
#endif

  private func reload() async {
    invites = []
    links = []
    children = []
    guard let supabase = appState.supabase, let orgId = appState.activeOrgId else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      invites = try await supabase.listMyParentInvites()
      links = try await supabase.listMyParentChildLinks(orgId: orgId)
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
      HPListScreenLayout {
        HPWorkspaceHeader(
          "Parent invites",
          context: "You have been invited to view one or more players as a parent/guardian."
        )
      } controls: {
        EmptyView()
      } results: { context in
        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            HPSectionHeader("Invites") {
              HPStatusBadge(text: "\(invites.count)", kind: .neutral)
            }
            ForEach(invites) { invite in
              let layout = context.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: HP.Space.sm))
                : AnyLayout(HStackLayout(alignment: .center, spacing: HP.Space.sm))
              layout {
                VStack(alignment: .leading, spacing: 4) {
                  Text("Player: \(invite.child_id.uuidString.prefix(6).uppercased())")
                    .font(HP.Font.headline)
                    .foregroundStyle(HP.Color.text)
                  if let relationship = invite.relationship,
                     !relationship.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(relationship)
                      .font(HP.Font.caption)
                      .foregroundStyle(HP.Color.textMuted)
                  }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HPButton(
                  title: "Accept",
                  systemImage: "checkmark",
                  variant: .secondary,
                  size: .sm,
                  fullWidth: context.isAccessibilitySize,
                  action: { onAccept(invite.id) }
                )
              }
              .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)

              if invite.id != invites.last?.id {
                Divider().overlay(HP.Color.border.opacity(0.5))
              }
            }
          }
        }
      }
      .navigationTitle("Parent invites")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Close") {
            invites = []
            dismiss()
          }
            #if os(macOS)
            .keyboardShortcut(.cancelAction)
            #endif
        }
      }
    }
  }
}
