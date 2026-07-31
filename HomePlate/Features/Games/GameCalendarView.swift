import SwiftUI

struct GameCalendarView: View {
  @EnvironmentObject private var appState: AppState

  @State private var visibleMonth = DateUtils.startOfMonthET(Date())
  @State private var selectedDate = DateUtils.startOfDayET(Date())
  @State private var items: [SDGameCalendarItem] = []
  @State private var selectedType: SDGameEventType?
  @State private var isLoading = false
  @State private var errorText: String?

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: DHDTheme.sectionSpacing) {
          DHDMonthGridView(
            visibleMonth: $visibleMonth,
            selectedDate: $selectedDate,
            scheduledLiftISOs: trainingDates,
            practiceISOs: practiceDates,
            gameISOs: gameDates,
            isLoading: isLoading,
            onPrev: { moveMonth(-1) },
            onNext: { moveMonth(1) },
            onSelect: { selectedDate = DateUtils.startOfDayET($0) }
          )

          eventTypeFilter
          agenda
        }
        .padding(DHDTheme.pagePadding)
      }
      .background(DHDTheme.pageBackground)
      .navigationTitle("Calendar")
      .refreshable { await reload() }
      .task(id: reloadKey) { await reload() }
      .alert("Calendar unavailable", isPresented: Binding(
        get: { errorText != nil },
        set: { if !$0 { errorText = nil } }
      )) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(errorText ?? "")
      }
    }
  }

  private var eventTypeFilter: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        filterButton("All", type: nil)
        filterButton("Games", type: .game)
        filterButton("Practices", type: .practice)
        filterButton("Training", type: .training)
        filterButton("Meetings", type: .meeting)
      }
    }
    .accessibilityLabel("Event type filter")
  }

  private func filterButton(_ title: String, type: SDGameEventType?) -> some View {
    Button {
      selectedType = type
    } label: {
      Text(title)
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 12)
        .frame(height: 34)
        .foregroundStyle(selectedType == type ? Color.white : DHDTheme.textPrimary)
        .background(selectedType == type ? DHDTheme.accent : DHDTheme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
    .buttonStyle(.plain)
  }

  private var agenda: some View {
    DHDCard {
      VStack(alignment: .leading, spacing: 12) {
        DHDSectionHeader(selectedDate.formatted(date: .complete, time: .omitted)) {
          Text("\(filteredDayItems.count)")
            .font(.caption.weight(.bold))
            .foregroundStyle(DHDTheme.textSecondary)
        }

        if filteredDayItems.isEmpty {
          ContentUnavailableView(
            "No events",
            systemImage: "calendar",
            description: Text("Nothing is scheduled for this day.")
          )
          .frame(maxWidth: .infinity)
          .padding(.vertical, 18)
        } else {
          ForEach(filteredDayItems) { item in
            NavigationLink {
              GameDetailView(calendarItem: item)
            } label: {
              GameCalendarRow(item: item)
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
  }

  private var filteredDayItems: [SDGameCalendarItem] {
    items.filter {
      Calendar.current.isDate($0.event.scheduled_start, inSameDayAs: selectedDate)
        && (selectedType == nil || $0.event.event_type == selectedType)
    }
  }

  private var trainingDates: Set<String> {
    dateSet(for: [.training, .testing])
  }

  private var practiceDates: Set<String> {
    dateSet(for: [.practice, .meeting, .organizationEvent])
  }

  private var gameDates: Set<String> {
    dateSet(for: [.game])
  }

  private func dateSet(for types: Set<SDGameEventType>) -> Set<String> {
    Set(items.filter { types.contains($0.event.event_type) }
      .map { DateUtils.toISODate($0.event.scheduled_start) })
  }

  private var reloadKey: String {
    "\(appState.activeOrgId?.uuidString ?? "none"):\(DateUtils.toISODate(visibleMonth))"
  }

  private func moveMonth(_ offset: Int) {
    visibleMonth = DateUtils.calendarET.date(
      byAdding: .month, value: offset, to: visibleMonth
    ) ?? visibleMonth
    selectedDate = DateUtils.startOfDayET(visibleMonth)
  }

  private func reload() async {
    guard let service = appState.supabase, let orgId = appState.activeOrgId else {
      items = []
      return
    }
    isLoading = true
    defer { isLoading = false }
    do {
      let start = DateUtils.startOfMonthET(visibleMonth)
      let end = DateUtils.calendarET.date(byAdding: .month, value: 1, to: start) ?? start
      let events = try await service.listCanonicalEvents(
        organizationId: orgId, from: start, through: end
      )
      let games = try await service.listGames(
        organizationId: orgId, eventIds: events.map(\.id)
      )
      let byEvent = Dictionary(uniqueKeysWithValues: games.map { ($0.event_id, $0) })
      items = events.map { SDGameCalendarItem(event: $0, game: byEvent[$0.id]) }
    } catch {
      items = []
      errorText = error.localizedDescription
    }
  }
}

private struct GameCalendarRow: View {
  let item: SDGameCalendarItem

  var body: some View {
    HStack(spacing: 12) {
      RoundedRectangle(cornerRadius: 3)
        .fill(statusColor)
        .frame(width: 5, height: 48)
      VStack(alignment: .leading, spacing: 3) {
        Text(item.event.title)
          .font(.headline)
          .foregroundStyle(DHDTheme.textPrimary)
        Text(timeAndVenue)
          .font(.caption)
          .foregroundStyle(DHDTheme.textSecondary)
      }
      Spacer()
      DHDStatusBadge(text: item.event.status.rawValue.replacingOccurrences(
        of: "_", with: " "
      ).capitalized, color: statusColor)
      Image(systemName: "chevron.right")
        .font(.caption.weight(.bold))
        .foregroundStyle(DHDTheme.textSecondary)
    }
    .padding(.vertical, 4)
    .contentShape(Rectangle())
  }

  private var timeAndVenue: String {
    let time = item.event.scheduled_start.formatted(date: .omitted, time: .shortened)
    guard let venue = item.event.location_name, !venue.isEmpty else { return time }
    return "\(time) • \(venue)"
  }

  private var statusColor: Color {
    switch item.event.status {
    case .live: .green
    case .delayed, .suspended, .postponed: .orange
    case .canceled, .noContest: .red
    case .final, .forfeit: .blue
    default: DHDTheme.accent
    }
  }
}
