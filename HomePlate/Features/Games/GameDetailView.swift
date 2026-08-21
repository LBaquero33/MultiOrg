import SwiftUI

struct GameDetailView: View {
  @EnvironmentObject private var appState: AppState

  let eventId: UUID?
  let gameId: UUID?
  @State private var item: SDGameCalendarItem?
  @State private var participants: [SDEventParticipant] = []
  @State private var attendance: [SDEventAttendance] = []
  @State private var attendanceRoster: [SDGameAttendanceRosterRow] = []
  @State private var isSavingAttendance = false
  @State private var attendanceMessage: String?
  @State private var errorText: String?
  @State private var selectedSection: SDGameWorkspaceSection = .overview

  init(calendarItem: SDGameCalendarItem) {
    eventId = calendarItem.event.id
    gameId = calendarItem.game?.id
    _item = State(initialValue: calendarItem)
  }

  init(eventId: UUID) {
    self.eventId = eventId
    gameId = nil
  }

  init(gameId: UUID) {
    eventId = nil
    self.gameId = gameId
  }

  var body: some View {
    ScrollView {
      if let item {
        VStack(alignment: .leading, spacing: DHDTheme.sectionSpacing) {
          DHDHeaderCard {
            VStack(alignment: .leading, spacing: 6) {
              Text(item.event.title).font(.title2.bold())
              Text(item.event.scheduled_start.formatted(date: .complete, time: .shortened))
              if let venue = item.event.location_name { Text(venue) }
            }
            .foregroundStyle(.white)
          }
          sectionPicker
          workspaceSection(item)
        }
        .padding(DHDTheme.pagePadding)
      } else {
        ProgressView("Loading event…").frame(maxWidth: .infinity, minHeight: 300)
      }
    }
    .background(DHDTheme.pageBackground)
    .navigationTitle("Event")
    .task(id: "\(appState.activeOrgId?.uuidString ?? ""):\(eventId?.uuidString ?? gameId?.uuidString ?? "")") {
      await load()
    }
    .alert("Game unavailable", isPresented: Binding(
      get: { errorText != nil }, set: { if !$0 { errorText = nil } }
    )) {
      Button("OK", role: .cancel) {}
    } message: { Text(errorText ?? "") }
  }

  private var sectionPicker: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(visibleSections) { section in
          Button(section.rawValue) { selectedSection = section }
            .buttonStyle(.bordered)
            .tint(selectedSection == section ? DHDTheme.accent : DHDTheme.textSecondary)
        }
      }
    }
  }

  private var visibleSections: [SDGameWorkspaceSection] {
    guard let item else { return [.overview] }
    if item.event.event_type != .game {
      return [.overview, .availability]
    }
    let status = item.event.status
    var result: [SDGameWorkspaceSection] = [.overview, .roster, .availability, .lineup, .rules]
    if [.live, .delayed, .suspended, .final, .forfeit].contains(status) {
      result += [.liveScore, .playByPlay]
    }
    if [.live, .delayed, .suspended, .final, .forfeit].contains(status) {
      result += [.boxScore, .playerStats, .postgameReview]
    }
    result.append(.gameNotes)
    return result
  }

  @ViewBuilder
  private func workspaceSection(_ item: SDGameCalendarItem) -> some View {
    DHDCard {
      VStack(alignment: .leading, spacing: 10) {
        DHDSectionHeader(selectedSection.rawValue) { EmptyView() }
        switch selectedSection {
        case .overview:
          if canRespondToAttendance(for: item.event) {
            playerAttendanceControl(for: item.event)
            Divider()
          }
          detail("Status", item.event.status.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
          if let game = item.game {
            detail("Matchup", "\(game.away_team_name) at \(game.home_team_name)")
            detail("Innings", "\(game.scheduled_innings)")
          }
          if let arrival = item.event.arrival_time {
            detail("Arrival", arrival.formatted(date: .omitted, time: .shortened))
          }
        case .roster:
          participantList(role: nil)
        case .availability:
          if appState.activeOrgMembership?.isStaff == true {
            staffAttendanceRoster
          } else if let response = myAttendance {
            detail(
              "Your response",
              response.expected_attendance == true ? "Coming" : "Not Coming"
            )
          } else {
            empty("You have not responded yet.")
          }
        case .lineup:
          empty(item.game?.lineup_ready == true ? "Lineup is ready." : "Lineup has not been submitted.")
        case .rules:
          detail("Scheduled innings", "\(item.game?.scheduled_innings ?? 0)")
          empty(item.game?.ruleset_id == nil ? "Default organization rules apply." : "A versioned game ruleset is attached.")
        case .liveScore:
          if let game = item.game {
            LiveGameScoringView(game: game, participants: participants)
          } else {
            empty("This event does not have a game record.")
          }
        case .boxScore:
          if let game = item.game { GameStatisticsView(game: game, mode: .boxScore) }
        case .playerStats:
          if let game = item.game { GameStatisticsView(game: game, mode: .players) }
        case .postgameReview:
          if let game = item.game {
            VStack(alignment: .leading, spacing: 16) {
              GameStatisticsView(game: game, mode: .decisions)
              Divider()
              GameFinalizationView(game: game, permissions: permissions) {
                await load()
              }
            }
          }
        case .playByPlay:
          if let game = item.game { PlayByPlayView(game: game) }
        case .gameNotes:
          empty("Game notes are visible only according to server authorization.")
        }
      }
    }
  }

  private var permissions: SDGameWorkspacePermissions {
    SDGameWorkspacePermissions.resolve(
      game: item?.game,
      activeOrganizationId: appState.activeOrgId,
      userId: appState.myProfile?.id,
      membership: appState.activeOrgMembership,
      participants: participants
    )
  }

  private var myAttendance: SDEventAttendance? {
    guard let playerId = appState.myProfile?.id else { return nil }
    return attendance.first { $0.player_id == playerId }
  }

  private func canRespondToAttendance(for event: SDCanonicalEvent) -> Bool {
    SDGameAttendanceAuthorization.canRespond(
      event: event,
      userId: appState.myProfile?.id,
      membership: appState.activeOrgMembership
    )
  }

  private func playerAttendanceControl(for event: SDCanonicalEvent) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Are you coming?")
        .font(.headline)
      Text("You can change your response at any time before the event.")
        .font(.footnote)
        .foregroundStyle(DHDTheme.textSecondary)
      HStack(spacing: 10) {
        attendanceButton(
          "Coming",
          symbol: "checkmark.circle.fill",
          attending: true,
          selected: myAttendance?.expected_attendance == true,
          color: .green,
          event: event
        )
        attendanceButton(
          "Not Coming",
          symbol: "xmark.circle.fill",
          attending: false,
          selected: myAttendance?.expected_attendance == false,
          color: .red,
          event: event
        )
      }
      if let attendanceMessage {
        Text(attendanceMessage)
          .font(.footnote)
          .foregroundStyle(attendanceMessage == "Response saved." ? .green : .red)
      }
    }
  }

  @ViewBuilder
  private var staffAttendanceRoster: some View {
    if attendanceRoster.isEmpty {
      empty("No players are assigned to this game.")
    } else {
      ForEach(SDGameAttendanceResponseGroup.allCases) { group in
        let players = attendanceRoster.filter(group.contains)
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Text(group.rawValue)
              .font(.headline)
              .foregroundStyle(attendanceColor(group))
            Spacer()
            Text("\(players.count)")
              .font(.caption.bold())
              .foregroundStyle(attendanceColor(group))
              .padding(.horizontal, 8)
              .padding(.vertical, 4)
              .background(attendanceColor(group).opacity(0.12))
              .clipShape(Capsule())
          }
          if players.isEmpty {
            Text("None")
              .font(.subheadline)
              .foregroundStyle(DHDTheme.textSecondary)
          } else {
            ForEach(players) { player in
              HStack(spacing: 8) {
                Image(systemName: attendanceSymbol(group))
                  .foregroundStyle(attendanceColor(group))
                Text(player.display_name)
                  .font(.subheadline.weight(.medium))
                Spacer()
              }
            }
          }
        }
        if group != .noResponse {
          Divider()
        }
      }
    }
  }

  private func attendanceColor(_ group: SDGameAttendanceResponseGroup) -> Color {
    switch group {
    case .coming: return .green
    case .notComing: return .red
    case .noResponse: return DHDTheme.textSecondary
    }
  }

  private func attendanceSymbol(_ group: SDGameAttendanceResponseGroup) -> String {
    switch group {
    case .coming: return "checkmark.circle.fill"
    case .notComing: return "xmark.circle.fill"
    case .noResponse: return "questionmark.circle"
    }
  }

  private func attendanceButton(
    _ title: String,
    symbol: String,
    attending: Bool,
    selected: Bool,
    color: Color,
    event: SDCanonicalEvent
  ) -> some View {
    Button {
      Task { await saveAttendance(attending, for: event) }
    } label: {
      Label(title, systemImage: symbol)
        .font(.subheadline.weight(.semibold))
        .frame(maxWidth: .infinity)
        .frame(height: 42)
        .foregroundStyle(selected ? .white : color)
        .background(selected ? color : color.opacity(0.10))
        .overlay(
          RoundedRectangle(cornerRadius: 7)
            .stroke(color.opacity(selected ? 1 : 0.55), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
    .buttonStyle(.plain)
    .disabled(isSavingAttendance)
    .accessibilityValue(selected ? "Selected" : "Not selected")
  }

  private func saveAttendance(_ attending: Bool, for event: SDCanonicalEvent) async {
    guard !isSavingAttendance,
          canRespondToAttendance(for: event),
          let service = appState.supabase,
          let orgId = appState.activeOrgId,
          let playerId = appState.myProfile?.id else { return }
    isSavingAttendance = true
    attendanceMessage = nil
    defer { isSavingAttendance = false }
    do {
      let saved = try await service.setExpectedGameAttendance(
        eventId: event.id,
        organizationId: orgId,
        playerId: playerId,
        attending: attending
      )
      attendance.removeAll { $0.player_id == playerId }
      attendance.append(saved)
      attendanceMessage = "Response saved."
    } catch {
      attendanceMessage = "Your response could not be saved. Please try again."
    }
  }

  @ViewBuilder
  private func participantList(role: String?) -> some View {
    let visible = participants.filter { role == nil || $0.role == role }
    if visible.isEmpty { empty("No participants are assigned.") }
    ForEach(visible) { participant in
      detail(participant.role?.replacingOccurrences(of: "_", with: " ").capitalized ?? "Participant",
             participant.user_id?.uuidString.prefix(8).description ?? "Team")
    }
  }

  private func empty(_ text: String) -> some View {
    Text(text).foregroundStyle(DHDTheme.textSecondary)
  }

  private func detail(_ label: String, _ value: String) -> some View {
    HStack { Text(label).foregroundStyle(DHDTheme.textSecondary); Spacer(); Text(value).fontWeight(.semibold) }
  }

  private func load() async {
    guard let service = appState.supabase, let orgId = appState.activeOrgId else { return }
    do {
      let event: SDCanonicalEvent
      let game: SDGame?
      if let gameId {
        let fetched = try await service.fetchGame(id: gameId, organizationId: orgId)
        game = fetched
        event = try await service.fetchCanonicalEvent(id: fetched.event_id, organizationId: orgId)
      } else if let eventId {
        event = try await service.fetchCanonicalEvent(id: eventId, organizationId: orgId)
        game = try? await service.fetchGameForEvent(eventId: eventId, organizationId: orgId)
      } else { return }
      item = SDGameCalendarItem(event: event, game: game)
      async let participantLoad = service.listEventParticipants(eventId: event.id, organizationId: orgId)
      async let attendanceLoad = service.listEventAttendance(eventId: event.id, organizationId: orgId)
      participants = try await participantLoad
      attendance = try await attendanceLoad
      if appState.activeOrgMembership?.isStaff == true {
        attendanceRoster = try await service.listGameAttendanceRoster(
          eventIds: [event.id],
          organizationId: orgId
        )
      } else {
        attendanceRoster = []
      }
    } catch {
      item = nil
      errorText = error.localizedDescription
    }
  }
}
