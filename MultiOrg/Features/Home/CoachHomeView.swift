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
    }
#else
    NavigationStack {
      List {
        Section {
          TextField("Search players", text: $query)
          #if canImport(UIKit)
            .textInputAutocapitalization(.never)
          #endif
            .autocorrectionDisabled()
            .textFieldStyle(RoundedBorderTextFieldStyle())
          Picker("Show", selection: $roleFilter) {
            ForEach(RoleFilter.allCases) { f in
              Text(f.rawValue).tag(f)
            }
          }
          .pickerStyle(.segmented)
        }

        Section(roleFilter.rawValue) {
          if isLoading {
            HStack(spacing: 10) {
              ProgressView()
              Text("Loading…").foregroundStyle(.secondary)
            }
          } else if filteredPlayers.isEmpty {
            Text("No players found.")
              .foregroundStyle(.secondary)
          } else {
            ForEach(filteredPlayers) { p in
              NavigationLink {
                CoachPlayerProfileView(player: p)
              } label: {
                HStack(spacing: 12) {
                  DHDAvatarView(
                    url: {
                      guard let path = p.avatar_path else { return nil }
                      return appState.supabase?.publicAvatarURL(path: path)
                    }(),
                    initials: String(p.displayName.prefix(2)).uppercased(),
                    size: 36
                  )
                  VStack(alignment: .leading, spacing: 2) {
                    Text(p.displayName).font(.headline)
                    Text("\(p.isCoach ? "Coach" : "Player") • \(p.shortId)")
                      .font(.caption)
                      .foregroundStyle(.secondary)
                  }
                }
                .padding(.vertical, 4)
              }
            }
          }
        }

        Section {
          Button(role: .destructive) {
            Task { await appState.signOut() }
          } label: {
            Text("Sign Out")
          }
        }
      }
      .navigationTitle("Coach")
      .toolbar {
        ToolbarItemGroup(placement: .cancellationAction) {
          Button("Programs") { showPrograms = true }
          Button("Roster Attention") { showRosterAttention = true }
        }
        ToolbarItem(placement: .primaryAction) {
          Button {
            Task { await reload() }
          } label: {
            Image(systemName: "arrow.clockwise")
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
              .foregroundStyle(DHDTheme.textPrimary)
          }
        }
        TableColumn("Role") { p in
          Text(p.isCoach ? "Coach" : "Player")
            .foregroundStyle(DHDTheme.textSecondary)
        }
        TableColumn("Last test") { p in
          Text(latestTestByPlayerId[p.id] ?? "—")
            .foregroundStyle(DHDTheme.textSecondary)
        }
        TableColumn("Program") { p in
          let name = activeProgramByPlayerId[p.id]
          if let name, !name.isEmpty {
            DHDStatusBadge(text: name, color: .green)
          } else {
            Text("—").foregroundStyle(DHDTheme.textSecondary)
          }
        }
        TableColumn("ID") { p in
          Text(p.shortId)
            .font(.caption.monospaced())
            .foregroundStyle(DHDTheme.textSecondary)
        }
      }
      .tableStyle(.inset)
      .onChange(of: selectedPlayerId) { _, newValue in
        selectedPlayerIdStorage = newValue?.uuidString ?? ""
      }
    }
    .background(DHDTheme.pageBackground)
    .toolbar {
      ToolbarItemGroup(placement: .automatic) {
        Picker("Show", selection: $roleFilter) {
          ForEach(RoleFilter.allCases) { f in
            Text(f.rawValue).tag(f)
          }
        }
        .pickerStyle(.segmented)

        Button {
          Task { await reload() }
        } label: {
          Image(systemName: "arrow.clockwise")
        }

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
      VStack(spacing: 10) {
        Text("Select a player")
          .font(.title3.weight(.semibold))
        Text("Choose a player from the roster to view their profile.")
          .foregroundStyle(DHDTheme.textSecondary)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(DHDTheme.pageBackground)
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
