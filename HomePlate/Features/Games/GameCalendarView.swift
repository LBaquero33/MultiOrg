import SwiftUI

struct GameCalendarView: View {
  @EnvironmentObject private var appState: AppState

  @State private var visibleMonth = DateUtils.startOfMonthET(Date())
  @State private var selectedDate = DateUtils.startOfDayET(Date())
  @State private var items: [SDGameCalendarItem] = []
  @State private var selectedType: SDGameEventType?
  @State private var isLoading = false
  @State private var errorText: String?
  @State private var editor: CanonicalEventEditorPresentation?

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
      .toolbar {
        if canCreateEvents {
          ToolbarItem(placement: .primaryAction) {
            Button {
              editor = CanonicalEventEditorPresentation(event: nil, duplicatesEvent: false)
            } label: {
              Label("New Event", systemImage: "plus")
            }
            .accessibilityIdentifier("calendar.newEvent")
          }
        }
      }
      .refreshable { await reload() }
      .task(id: reloadKey) { await reload() }
      .sheet(item: $editor) { presentation in
        CanonicalEventEditorView(
          event: presentation.event,
          duplicatesEvent: presentation.duplicatesEvent,
          teams: appState.authorizedScheduleTeams
        ) {
          editor = nil
          Task { await reload() }
        }
        .environmentObject(appState)
      }
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
            HStack(spacing: 6) {
              NavigationLink {
                GameDetailView(calendarItem: item)
              } label: {
                GameCalendarRow(item: item)
              }
              .buttonStyle(.plain)
              if canCreateEvents {
                Menu {
                  Button {
                    editor = CanonicalEventEditorPresentation(event: item.event, duplicatesEvent: false)
                  } label: {
                    Label("Edit Event", systemImage: "pencil")
                  }
                  Button {
                    editor = CanonicalEventEditorPresentation(event: item.event, duplicatesEvent: true)
                  } label: {
                    Label("Duplicate Event", systemImage: "plus.square.on.square")
                  }
                  if item.event.status != .canceled {
                    Button(role: .destructive) {
                      Task { await cancel(item.event) }
                    } label: {
                      Label("Cancel Event", systemImage: "calendar.badge.minus")
                    }
                  }
                } label: {
                  Image(systemName: "ellipsis.circle")
                    .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Actions for \(item.event.title)")
              }
            }
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

  private var canCreateEvents: Bool {
    appState.canAdminActiveOrg || !appState.authorizedScheduleTeams.isEmpty
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
      errorText = items.isEmpty
        ? "Events could not be loaded. Check your connection and try again."
        : "Calendar may be out of date. Previously loaded events remain visible."
    }
  }

  private func cancel(_ event: SDCanonicalEvent) async {
    guard let service = appState.supabase, let orgId = appState.activeOrgId else { return }
    do {
      try await service.cancelCanonicalEvent(id: event.id, organizationId: orgId)
      await reload()
    } catch {
      errorText = "This event could not be canceled. Confirm your team permissions and try again."
    }
  }
}

private struct CanonicalEventEditorPresentation: Identifiable {
  let id = UUID()
  let event: SDCanonicalEvent?
  let duplicatesEvent: Bool
}

private struct CanonicalEventEditorView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var appState: AppState

  let event: SDCanonicalEvent?
  let duplicatesEvent: Bool
  let teams: [SDTeamOperationsTeam]
  let onSaved: () -> Void

  @State private var title: String
  @State private var eventType: SDGameEventType
  @State private var description: String
  @State private var start: Date
  @State private var end: Date
  @State private var includesArrival: Bool
  @State private var arrival: Date
  @State private var locationName: String
  @State private var venueAddress: String
  @State private var selectedTeamId: UUID?
  @State private var opponentName: String
  @State private var gameSite: SDGameSite
  @State private var scheduledInnings: Int
  @State private var isSaving = false
  @State private var errorText: String?

  init(
    event: SDCanonicalEvent?,
    duplicatesEvent: Bool,
    teams: [SDTeamOperationsTeam],
    onSaved: @escaping () -> Void
  ) {
    self.event = event
    self.duplicatesEvent = duplicatesEvent
    self.teams = teams
    self.onSaved = onSaved
    let defaultStart = event?.scheduled_start ?? Date().addingTimeInterval(3_600)
    _title = State(initialValue: event?.title ?? "")
    _eventType = State(initialValue: event?.event_type ?? .practice)
    _description = State(initialValue: event?.description ?? "")
    _start = State(initialValue: defaultStart)
    _end = State(initialValue: event?.scheduled_end ?? defaultStart.addingTimeInterval(5_400))
    _includesArrival = State(initialValue: event?.arrival_time != nil)
    _arrival = State(initialValue: event?.arrival_time ?? defaultStart.addingTimeInterval(-1_800))
    _locationName = State(initialValue: event?.location_name ?? "")
    _venueAddress = State(initialValue: event?.venue_address ?? "")
    _selectedTeamId = State(initialValue: event?.team_id ?? teams.first?.id)
    _opponentName = State(initialValue: event?.event_type == .game ? event?.title ?? "" : "")
    _gameSite = State(initialValue: .home)
    _scheduledInnings = State(initialValue: 7)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Event") {
          TextField("Event name", text: $title)
          Picker("Type", selection: $eventType) {
            ForEach(SDGameEventType.allCases.filter { $0 != .facilityBooking }, id: \.self) { type in
              Text(eventTypeLabel(type)).tag(type)
            }
          }
          Picker("Audience", selection: $selectedTeamId) {
            if appState.canAdminActiveOrg {
              Text("Entire organization").tag(UUID?.none)
            }
            ForEach(teams) { team in
              Text(team.name).tag(Optional(team.id))
            }
          }
          TextField("Description", text: $description, axis: .vertical)
        }
        if eventType == .game {
          Section("Game details") {
            TextField("Opponent", text: $opponentName)
            Picker("Site", selection: $gameSite) {
              ForEach(SDGameSite.allCases, id: \.self) { site in
                Text(site.rawValue.capitalized).tag(site)
              }
            }
            Stepper("Scheduled innings: \(scheduledInnings)", value: $scheduledInnings, in: 1...20)
          }
        }
        Section("Date and time") {
          DatePicker("Starts", selection: $start)
          DatePicker("Ends", selection: $end, in: start...)
          Toggle("Set arrival time", isOn: $includesArrival)
          if includesArrival {
            DatePicker("Arrival", selection: $arrival, in: ...start)
          }
        }
        Section("Location") {
          TextField("Location", text: $locationName)
          TextField("Address", text: $venueAddress)
        }
        if let errorText {
          Section {
            Label(errorText, systemImage: "exclamationmark.triangle.fill")
              .foregroundStyle(.red)
          }
        }
      }
      .navigationTitle(event == nil || duplicatesEvent ? "New Event" : "Edit Event")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") { Task { await save() } }
            .disabled(isSaving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || end <= start)
        }
      }
    }
  }

  private func save() async {
    guard !isSaving,
          let service = appState.supabase,
          let organizationId = appState.activeOrgId else { return }
    isSaving = true
    defer { isSaving = false }
    let draft = SupabaseService.SDCanonicalEventDraft(
      title: title.trimmingCharacters(in: .whitespacesAndNewlines),
      eventType: eventType,
      description: description,
      start: start,
      end: end,
      arrival: includesArrival ? arrival : nil,
      locationName: locationName,
      venueAddress: venueAddress,
      facilityId: event?.facility_id,
      teamId: selectedTeamId,
      visibility: selectedTeamId == nil ? .organization : .team,
      opponentName: opponentName,
      gameSite: gameSite,
      scheduledInnings: scheduledInnings
    )
    do {
      if let event, !duplicatesEvent {
        _ = try await service.updateCanonicalEvent(
          id: event.id,
          organizationId: organizationId,
          draft: draft
        )
      } else {
        _ = try await service.createCanonicalEvent(
          organizationId: organizationId,
          draft: draft
        )
      }
      onSaved()
      dismiss()
    } catch {
      errorText = "This event could not be saved. Confirm your team permissions and try again."
    }
  }

  private func eventTypeLabel(_ type: SDGameEventType) -> String {
    switch type {
    case .facilityBooking: return "Facility booking"
    case .organizationEvent: return "Organization event"
    default: return type.rawValue.capitalized
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
