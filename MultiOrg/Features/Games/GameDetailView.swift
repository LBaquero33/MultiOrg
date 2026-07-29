import SwiftUI

struct GameDetailView: View {
  @EnvironmentObject private var appState: AppState

  let eventId: UUID?
  let gameId: UUID?
  @State private var item: SDGameCalendarItem?
  @State private var participants: [SDEventParticipant] = []
  @State private var attendance: [SDEventAttendance] = []
  @State private var errorText: String?

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
          DHDCard {
            VStack(alignment: .leading, spacing: 10) {
              DHDSectionHeader("Overview") { EmptyView() }
              detail("Status", item.event.status.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
              if let game = item.game {
                detail("Matchup", "\(game.away_team_name) at \(game.home_team_name)")
                detail("Innings", "\(game.scheduled_innings)")
                detail("Availability", "\(attendance.count) responses")
              }
            }
          }
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
