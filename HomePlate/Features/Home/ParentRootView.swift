import SwiftUI

/// Parent root: Children, calendar, chat, and account.
struct ParentRootView: View {
  @EnvironmentObject private var appState: AppState
  @State private var selection: HPAppNavigationDestination = .parentHome

  var body: some View {
    Group {
#if os(iOS)
      HPAdaptiveApplicationShell(
        role: .parent,
        roleSubtitle: "Parent workspace",
        inventory: navigationInventory,
        selection: $selection
      ) { destination in
        destinationView(destination)
      }
#else
      HPRegularApplicationShell(
        role: .parent,
        inventory: navigationInventory,
        selection: $selection
      ) { destination in
        destinationView(destination)
      }
#endif
    }
    .onChange(of: appState.requestedChatChannelId) { _, channelId in
      guard channelId != nil, feature("chat") else { return }
      selection = .chat
    }
    .task(id: appState.requestedChatChannelId) {
      guard appState.requestedChatChannelId != nil, feature("chat") else { return }
      selection = .chat
    }
  }

  private var navigationInventory: HPAppNavigationInventory {
    .parent(
      childrenTitle: term("players", fallback: "Children"),
      chatEnabled: feature("chat")
    )
  }

  @ViewBuilder
  private func destinationView(_ destination: HPAppNavigationDestination) -> some View {
    switch destination {
    case .parentHome:
      ParentHomeView()
    case .parentChildren:
      ParentHomeView()
    case .parentCalendar:
      GameCalendarView()
    case .playerProgram:
      UnifiedPlayerDevelopmentWorkspaceView()
    case .chat:
      if feature("chat") {
        ChatChannelListView()
      }
    case .payments:
#if os(iOS)
      NavigationStack { ParentPaymentsWorkspaceView() }
#else
      ParentPaymentsWorkspaceView()
#endif
    case .account:
#if os(iOS)
      NavigationStack { AccountView() }
#else
      AccountView()
#endif
    default:
      EmptyView()
    }
  }

  private func term(_ key: String, fallback: String) -> String {
    appState.activeOrgSettings?.term(key, fallback: fallback) ?? fallback
  }

  private func feature(_ key: String) -> Bool {
    appState.activeOrgSettings?.feature(key) ?? true
  }
}

private struct ParentPaymentsWorkspaceView: View {
  @EnvironmentObject private var appState: AppState
  @State private var children: [Profile] = []
  @State private var isLoading = false
  @State private var errorText: String?

  var body: some View {
    HPListScreenLayout {
      HPWorkspaceHeader(
        "Payments",
        context: "Choose a child to review organization payment requests"
      )
    } controls: {
      EmptyView()
    } results: { _ in
      HPCard {
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          HPSectionHeader("Children") {
            if isLoading { ProgressView().controlSize(.small) }
          }

          if let errorText {
            HPErrorState(message: errorText, onRetry: { Task { await reload() } })
          } else if children.isEmpty, !isLoading {
            HPEmptyState(
              title: "No linked children",
              message: "Payment requests appear after a player is linked to this parent account.",
              systemImage: "person.2"
            )
          } else {
            ForEach(children) { child in
              NavigationLink {
                SDParentBillingView(child: child)
              } label: {
                HStack(spacing: HP.Space.sm) {
                  DHDAvatarView(
                    url: child.avatar_path.flatMap { appState.supabase?.publicAvatarURL(path: $0) },
                    initials: String(child.displayName.prefix(2)).uppercased(),
                    size: 40
                  )
                  VStack(alignment: .leading, spacing: 2) {
                    Text(child.displayName)
                      .font(HP.Font.headline)
                      .foregroundStyle(HP.Color.text)
                    Text("View payment requests")
                      .font(HP.Font.caption)
                      .foregroundStyle(HP.Color.textMuted)
                  }
                  Spacer()
                  Image(systemName: "chevron.right")
                    .foregroundStyle(HP.Color.textMuted)
                }
                .frame(minHeight: 48)
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
    .refreshable { await reload() }
    .task(id: appState.activeOrgAuthorizationKey) { await reload() }
  }

  private func reload() async {
    errorText = nil
    guard let service = appState.supabase, let organizationId = appState.activeOrgId else {
      children = []
      errorText = "Choose an organization to view payment requests."
      return
    }

    isLoading = true
    defer { isLoading = false }
    do {
      let links = try await service.listMyParentChildLinks(orgId: organizationId)
      let profiles = try await service.listProfiles(ids: links.map(\.child_id))
      guard appState.activeOrgId == organizationId else { return }
      children = profiles.filter(\.isPlayer).sorted { $0.displayName < $1.displayName }
    } catch {
      errorText = SDApplicationErrorClassifier.alertMessage(for: error)
    }
  }
}
