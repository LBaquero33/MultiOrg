import SwiftUI

struct GameDetailView: View {
  @EnvironmentObject private var appState: AppState

  let eventId: UUID?
  let gameId: UUID?
  @State private var item: SDGameCalendarItem?
  @State private var participants: [SDEventParticipant] = []
  @State private var attendance: [SDEventAttendance] = []
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
    .navigationTitle("Game")
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
    guard let status = item?.event.status else { return [.overview] }
    var result: [SDGameWorkspaceSection] = [.overview, .roster, .availability, .lineup, .rules]
    if [.live, .delayed, .suspended, .final, .forfeit].contains(status) {
      result += [.liveScore, .playByPlay]
    }
    if [.final, .forfeit].contains(status) {
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
          if attendance.isEmpty { empty("No availability responses yet.") }
          ForEach(attendance) { response in
            detail(response.player_id.uuidString.prefix(8).description, response.availability.capitalized)
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
          if let game = item.game { GameStatisticsView(game: game, mode: .decisions) }
        case .playByPlay:
          empty("This section uses the canonical game state and becomes available as scoring data is committed.")
        case .gameNotes:
          empty("Game notes are visible only according to server authorization.")
        }
      }
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
    } catch {
      item = nil
      errorText = error.localizedDescription
    }
  }
}
