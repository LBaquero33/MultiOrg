import SwiftUI

struct CoachHomeView: View {
  @EnvironmentObject private var appState: AppState
  @State private var players: [Profile] = []
  @State private var isLoading = false
  @State private var query = ""
  @State private var showPrograms = false
  @State private var showRosterAttention = false
  @State private var roleFilter: RoleFilter = .players

#if os(macOS)
  @SceneStorage("coach.selectedPlayerId") private var selectedPlayerIdStorage: String = ""
  @State private var selectedPlayerId: UUID?
  @State private var activeProgramByPlayerId: [UUID: String] = [:]
  @State private var latestTestByPlayerId: [UUID: String] = [:]
#endif

  enum RoleFilter: String, CaseIterable, Identifiable {
    case players = "Players"
    case coaches = "Coaches"
    case all = "All"
    var id: String { rawValue }
  }

  private var filteredPlayers: [Profile] {
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let base: [Profile] = players.filter { p in
      switch roleFilter {
      case .players: return p.isPlayer
      case .coaches: return p.isCoach
      case .all: return true
      }
    }
    guard !q.isEmpty else { return base }
    return base.filter { p in
      p.displayName.lowercased().contains(q) || p.shortId.lowercased().contains(q)
    }
  }

  var body: some View {
#if os(macOS)
    HStack(spacing: 0) {
      rosterPane
        .frame(width: 360)
      Divider()
      detailPane
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .navigationTitle(selectedPlayer?.displayName ?? "Coach")
    .task { await reload() }
    .sheet(isPresented: $showRosterAttention) {
      DevelopmentRosterAttentionView(players: players)
        .environmentObject(appState)
        .onExitCommand { showRosterAttention = false }
    }
#else
    NavigationStack {
      HPWorkspaceScreenLayout {
        HPWorkspaceHeader(
          "Coach",
          orgLabel: activeOrganizationName,
          context: "Roster workspace • \(filteredPlayers.count) shown"
        ) {
          HPButton(
            title: "Programs",
            systemImage: "list.clipboard",
            variant: .primary,
            size: .sm,
            action: { showPrograms = true }
          )
        }
      } attention: {
        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            HPSearchBar(text: $query, placeholder: "Search players")
              #if canImport(UIKit)
              .textInputAutocapitalization(.never)
              #endif
              .autocorrectionDisabled()
            VStack(alignment: .leading, spacing: 6) {
              Text("SHOW")
                .font(HP.Font.eyebrow)
                .tracking(HP.Font.eyebrowTracking)
                .foregroundStyle(HP.Color.textMuted)
              HPSegmentedControl(
                options: RoleFilter.allCases.map { (value: $0, label: $0.rawValue) },
                selection: $roleFilter
              )
            }
          }
        }
      } metrics: {
        HPMetricCard(
          title: "Roster",
          value: "\(players.count)",
          context: "All profiles"
        )
        HPMetricCard(
          title: "Showing",
          value: "\(filteredPlayers.count)",
          context: roleFilter.rawValue
        )
      } supporting: {
        rosterResults
      }
      .navigationTitle("Coach")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            showRosterAttention = true
          } label: {
            Label("Roster Attention", systemImage: "exclamationmark.bubble")
          }
        }
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
              .accessibilityLabel("More coach actions")
          }
        }
      }
      .sheet(isPresented: $showPrograms) {
        CoachProgramsView()
          .environmentObject(appState)
      }
      .sheet(isPresented: $showRosterAttention) {
        DevelopmentRosterAttentionView(players: players)
          .environmentObject(appState)
      }
      .task {
        await reload()
      }
    }
#endif
  }

  private var activeOrganizationName: String {
    if let organizationId = appState.activeOrgId,
       let organization = appState.availableOrganizations.first(where: { $0.id == organizationId }) {
      return organization.displayName
    }
    return appState.activeOrgSettings?.display_name
      ?? appState.activeOrgSettings?.short_name
      ?? "Home Plate"
  }

#if !os(macOS)
  private var rosterResults: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader(roleFilter.rawValue) {
          HPStatusBadge(text: "\(filteredPlayers.count)", kind: .neutral)
        }

        if isLoading {
          HPLoadingState(text: "Loading…")
        } else if filteredPlayers.isEmpty {
          HPEmptyState(
            title: "No players found.",
            message: "Try another search or role filter.",
            systemImage: "person.2"
          )
        } else {
          ForEach(filteredPlayers) { player in
            NavigationLink {
              CoachPlayerProfileView(player: player)
            } label: {
              rosterRow(player)
            }
            .buttonStyle(.plain)

            if player.id != filteredPlayers.last?.id {
              Divider().overlay(HP.Color.border.opacity(0.5))
            }
          }
        }
      }
    }
  }

  private func rosterRow(_ player: Profile) -> some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: HP.Space.sm) {
        rosterIdentity(player)
          .fixedSize(horizontal: true, vertical: false)
        Spacer(minLength: HP.Space.xs)
        Image(systemName: "chevron.right")
          .font(.caption.weight(.semibold))
          .foregroundStyle(HP.Color.textMuted)
          .accessibilityHidden(true)
      }

      VStack(alignment: .leading, spacing: HP.Space.sm) {
        rosterIdentity(player)
        Label("Open profile", systemImage: "chevron.right")
          .font(HP.Font.caption.weight(.semibold))
          .foregroundStyle(HP.Color.accent)
      }
    }
    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    .contentShape(Rectangle())
  }

  private func rosterIdentity(_ player: Profile) -> some View {
    HStack(spacing: HP.Space.sm) {
      DHDAvatarView(
        url: {
          guard let path = player.avatar_path else { return nil }
          return appState.supabase?.publicAvatarURL(path: path)
        }(),
        initials: String(player.displayName.prefix(2)).uppercased(),
        size: 36
      )
      VStack(alignment: .leading, spacing: 2) {
        Text(player.displayName)
          .font(HP.Font.headline)
          .foregroundStyle(HP.Color.text)
          .fixedSize(horizontal: false, vertical: true)
        Text("\(player.isCoach ? "Coach" : "Player") • \(player.shortId)")
          .font(HP.Font.caption)
          .foregroundStyle(HP.Color.textMuted)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }
#endif

  private func reload() async {
    guard let supabase = appState.supabase else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      players = try await supabase.listPlayerProfiles()
#if os(macOS)
      hydrateSelection()
      await loadRosterBadges()
#endif
    } catch {
      players = []
      appState.authError = error.localizedDescription
    }
  }

#if os(macOS)
  private var selectedPlayer: Profile? {
    guard let selectedPlayerId else { return nil }
    return players.first(where: { $0.id == selectedPlayerId })
  }

  private var rosterPane: some View {
    VStack(spacing: 0) {
      HPWorkspaceHeader(
        "Roster",
        orgLabel: activeOrganizationName,
        context: "\(filteredPlayers.count) \(filteredPlayers.count == 1 ? "person" : "people") shown"
      )
      .padding(HP.Space.sm)

      if isLoading {
        HPLoadingState(text: "Loading roster…")
          .padding(.horizontal, HP.Space.md)
          .padding(.bottom, HP.Space.sm)
      }

      Table(filteredPlayers, selection: $selectedPlayerId) {
        TableColumn("Name") { p in
          HStack(spacing: 10) {
            DHDAvatarView(
              url: {
                guard let path = p.avatar_path else { return nil }
                return appState.supabase?.publicAvatarURL(path: path)
              }(),
              initials: String(p.displayName.prefix(2)).uppercased(),
              size: 26
            )
            Text(p.displayName)
              .font(HP.Font.callout)
              .foregroundStyle(HP.Color.text)
          }
        }
        TableColumn("Role") { p in
          Text(p.isCoach ? "Coach" : "Player")
            .font(HP.Font.caption)
            .foregroundStyle(HP.Color.textMuted)
        }
        TableColumn("Last test") { p in
          Text(latestTestByPlayerId[p.id] ?? "—")
            .font(HP.Font.caption)
            .foregroundStyle(HP.Color.textMuted)
        }
        TableColumn("Program") { p in
          let name = activeProgramByPlayerId[p.id]
          if let name, !name.isEmpty {
            HPStatusBadge(text: name, kind: .success)
          } else {
            Text("—").foregroundStyle(HP.Color.textMuted)
          }
        }
        TableColumn("ID") { p in
          Text(p.shortId)
            .font(.caption.monospaced())
            .foregroundStyle(HP.Color.textMuted)
        }
      }
      .tableStyle(.inset)
      .onChange(of: selectedPlayerId) { _, newValue in
        selectedPlayerIdStorage = newValue?.uuidString ?? ""
      }
    }
    .background(HP.Color.bg)
    .toolbar {
      ToolbarItemGroup(placement: .automatic) {
        Picker("Show", selection: $roleFilter) {
          ForEach(RoleFilter.allCases) { f in
            Text(f.rawValue).tag(f)
          }
        }
        .pickerStyle(.segmented)
        .tint(HP.Color.accent)

        Button {
          Task { await reload() }
        } label: {
          Image(systemName: "arrow.clockwise")
        }
        .accessibilityLabel("Refresh roster")

        Button {
          showRosterAttention = true
        } label: {
          Label("Roster Attention", systemImage: "exclamationmark.bubble")
        }
      }
    }
    .searchable(text: $query, placement: .toolbar, prompt: "Search")
  }

  @ViewBuilder
  private var detailPane: some View {
    if let p = selectedPlayer {
      CoachPlayerProfileView(player: p)
        .id(p.id)
        .environmentObject(appState)
    } else {
      HPStateScreenLayout { _ in
        HPCard {
          HPEmptyState(
            title: "Select a player",
            message: "Choose a player from the roster to view their profile.",
            systemImage: "person.crop.circle"
          )
        }
      }
    }
  }

  private func hydrateSelection() {
    if let uuid = UUID(uuidString: selectedPlayerIdStorage), players.contains(where: { $0.id == uuid }) {
      selectedPlayerId = uuid
    } else {
      selectedPlayerId = filteredPlayers.first?.id
      selectedPlayerIdStorage = selectedPlayerId?.uuidString ?? ""
    }
    if let current = selectedPlayerId, !filteredPlayers.contains(where: { $0.id == current }) {
      selectedPlayerId = filteredPlayers.first?.id
      selectedPlayerIdStorage = selectedPlayerId?.uuidString ?? ""
    }
  }

  private func loadRosterBadges() async {
    guard let supabase = appState.supabase else { return }
    let ids = players.map(\.id)
    do {
      activeProgramByPlayerId = try await supabase.fetchActiveProgramNames(playerIds: ids)
      latestTestByPlayerId = try await supabase.fetchLatestTestDates(playerIds: ids)
    } catch {
      // Best-effort; keep UI usable if badge queries fail.
      activeProgramByPlayerId = [:]
      latestTestByPlayerId = [:]
    }
  }
#endif
}
