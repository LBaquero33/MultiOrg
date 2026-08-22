import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

private struct PendingProgramSetVideo {
  let data: Data
  let fileExtension: String
  let mimeType: String
}

struct SDPlayerTodayView: View {
  var body: some View {
    NavigationStack {
      SDPlayerTodayViewInternal(initialDate: Date())
    }
  }
}

struct SDPlayerTodayViewInternal: View {
  @EnvironmentObject private var appState: AppState
  @Environment(\.scenePhase) private var scenePhase

  let initialDate: Date
  @State private var date: Date
  @State private var assignment: SDProgramAssignment?
  @State private var template: SDProgramTemplate?
  @State private var exercises: [SDExercise] = []
  @State private var strengthLogs: [SDStrengthLog] = []
  @State private var testingEntries: [SDTestingEntry] = []
  @State private var teamEvents: [SDCanonicalEvent] = []
  @State private var eventAttendance: [UUID: Bool] = [:]
  @State private var attendanceSavingEventIds: Set<UUID> = []
  @State private var selectedEvent: SDCanonicalEvent?
  @State private var changingAttendanceEventIds: Set<UUID> = []
  @State private var todayAggregate: SDTodayResponse?
  @State private var todayServiceError: String?
  @State private var todayLoadToken: UUID?
  @State private var todayPublishedContext: String?
  @State private var weightEntries: [String: [String]] = [:]
  @State private var noWeight: [String: Bool] = [:]
  @State private var setsCompleted: [String: Int] = [:]
  @State private var perExerciseNotes: [String: String] = [:]
  @State private var programSetMedia: [String: SDProgramSetMedia] = [:]
  @State private var pendingSetVideoData: [String: PendingProgramSetVideo] = [:]

  @State private var isLoading = false
  @State private var isSaving = false
  @State private var errorText: String?
  @State private var successToast: String?

  @State private var isStrengthExpanded = true

  init(initialDate: Date) {
    self.initialDate = initialDate
    _date = State(initialValue: initialDate)
  }

  var body: some View {
    HPProgramExecutionLayout {
      header
    } dateContext: {
      dateContextCard
    } programSummary: {
      playerTodayAttentionCard
      playerBaseballDayCard
      improvementCard
      programCard
    } activities: {
      if scheduleContext?.isScheduled == true {
        strengthLoggerCard
      }
    } subActivities: {
      SDPlayerBPDaySection(date: date)
    } assessment: {
      EmptyView()
    } submission: {
      submitCard
    }
    .navigationTitle("Today")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          Button {
            Task { await reloadAll() }
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
    .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { _ in errorText = nil })) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(errorText ?? "")
    }
    .hpToast($successToast)
    .sheet(item: $selectedEvent) { event in
      NavigationStack {
        GameDetailView(eventId: event.id)
          .toolbar {
            ToolbarItem(placement: .cancellationAction) {
              Button("Close") { selectedEvent = nil }
            }
          }
      }
    }
    .task(id: todayContextIdentity) {
      await reloadAll()
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { Task { await reloadAll() } }
    }
  }

  private var dateISO: String { DateUtils.toISODate(date) }
  private var todayContextIdentity: String {
    "\(appState.activeOrgAuthorizationKey):\(appState.myProfile?.id.uuidString ?? "none"):\(appState.selectedSeason?.id.uuidString ?? "none"):\(dateISO):\(TimeZone.current.identifier)"
  }

  private var playerBaseballDayCard: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Upcoming team schedule") {
          HPStatusBadge(text: "\(teamEvents.count) upcoming", kind: teamEvents.isEmpty ? .neutral : .info)
        }
        if teamEvents.isEmpty {
          HPEmptyState(
            title: "No upcoming team events",
            message: "Your next practice, team event, or game will appear here.",
            systemImage: "calendar"
          )
        } else {
          ForEach(teamEvents) { event in
            VStack(alignment: .leading, spacing: HP.Space.xs) {
              HStack {
                VStack(alignment: .leading, spacing: 2) {
                  Text(event.event_type == .game ? "NEXT GAME" : "NEXT TEAM EVENT")
                    .font(HP.Font.eyebrow)
                    .tracking(HP.Font.eyebrowTracking)
                    .foregroundStyle(HP.Color.textMuted)
                  Button { selectedEvent = event } label: {
                    Label(event.title, systemImage: event.event_type.systemImage)
                      .font(HP.Font.headline).foregroundStyle(HP.Color.text)
                  }
                  .buttonStyle(.plain)
                }
                Spacer()
                HPStatusBadge(text: event.status.rawValue.capitalized, kind: .info)
              }
              Text("\(event.event_type.label) • \(event.scheduled_start.formatted(date: .abbreviated, time: .shortened))")
                .font(HP.Font.callout).foregroundStyle(HP.Color.textMuted)
              if let arrival = event.arrival_time {
                Label("Arrive \(arrival.formatted(date: .omitted, time: .shortened))", systemImage: "figure.walk.arrival")
              }
              if let location = event.location_name?.sdNilIfBlank { Label(location, systemImage: "mappin") }
              if event.status == .postponed {
                Label("Event postponed", systemImage: "clock.badge.exclamationmark")
                  .foregroundStyle(HP.Color.warning)
              }
              if let attending = eventAttendance[event.id], !changingAttendanceEventIds.contains(event.id) {
                HStack(spacing: HP.Space.sm) {
                  HPStatusBadge(text: attending ? "Coming" : "Not Coming", kind: attending ? .success : .danger)
                  Button("Change") { changingAttendanceEventIds.insert(event.id) }
                    .font(HP.Font.caption.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(HP.Color.accent)
                }
              } else {
                HStack(spacing: HP.Space.sm) {
                  attendanceButton(
                    event: event,
                    title: "Coming",
                    systemImage: "checkmark.circle.fill",
                    color: .green,
                    selected: eventAttendance[event.id] == true,
                    attending: true
                  )
                  attendanceButton(
                    event: event,
                    title: "Not Coming",
                    systemImage: "xmark.circle.fill",
                    color: .red,
                    selected: eventAttendance[event.id] == false,
                    attending: false
                  )
                }
              }
            }
            .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
            if event.id != teamEvents.last?.id { Divider() }
          }
        }
      }
    }
  }

  private func attendanceButton(
    event: SDCanonicalEvent,
    title: String,
    systemImage: String,
    color: Color,
    selected: Bool,
    attending: Bool
  ) -> some View {
    Button {
      respondToEvent(event, attending: attending)
    } label: {
      Label(title, systemImage: systemImage)
        .font(HP.Font.callout.weight(.semibold))
        .frame(maxWidth: .infinity, minHeight: 44)
        .foregroundStyle(selected ? Color.white : color)
        .background(selected ? color : color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: HP.Radius.md))
    }
    .buttonStyle(.plain)
    .disabled(attendanceSavingEventIds.contains(event.id) || event.status == .postponed)
  }

  @ViewBuilder private var playerTodayAttentionCard: some View {
    if let todayServiceError {
      HPCard {
        HPErrorState(
          title: "Today’s mission summary is unavailable",
          message: todayServiceError,
          onRetry: { Task { await reloadTodayAggregate() } }
        )
      }
    } else if let aggregate = todayAggregate,
              !aggregate.attention_items.isEmpty || aggregate.services.values.contains(where: { ![.available, .unauthorized].contains($0.state) }) {
      HPCard {
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          HPSectionHeader("My attention") {
            HPStatusBadge(text: "\(aggregate.attention_items.count)", kind: aggregate.attention_items.isEmpty ? .neutral : .warning)
          }
          ForEach(aggregate.attention_items) { item in
            Label(item.title, systemImage: item.severity == .urgent ? "exclamationmark.triangle.fill" : "exclamationmark.circle")
              .font(HP.Font.callout).foregroundStyle(HP.Color.text)
          }
          ForEach(aggregate.services.keys.sorted(), id: \.self) { name in
            if let state = aggregate.services[name], ![.available, .unauthorized].contains(state.state) {
              Label(state.message ?? "This section is temporarily unavailable.", systemImage: "wifi.exclamationmark")
                .font(HP.Font.caption).foregroundStyle(HP.Color.warning)
            }
          }
        }
      }
    }
  }

  private var scheduleContext: SDProgramSchedule.DayContext? {
    guard let assignment, let template else { return nil }
    return SDProgramSchedule.context(for: date, assignment: assignment, template: template)
  }

  private var header: some View {
    HPWorkspaceHeader("Today", context: DateUtils.prettyDateTitle(date)) {
      HStack(spacing: HP.Space.xs) {
        HPStatusBadge(text: scheduleContext?.isScheduled == true ? "Scheduled" : "Off day",
                      kind: scheduleContext?.isScheduled == true ? .success : .neutral)
        HPStatusBadge(text: isDaySaved ? "Saved" : "Not logged",
                      kind: isDaySaved ? .success : .warning)
      }
    }
  }

  private var dateContextCard: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HStack(alignment: .firstTextBaseline, spacing: HP.Space.sm) {
          Text("Viewing")
            .font(HP.Font.caption)
            .foregroundStyle(HP.Color.textMuted)
          DatePicker("", selection: $date, displayedComponents: .date)
            .datePickerStyle(.compact)
            .labelsHidden()
            .tint(HP.Color.accent)
            .onChange(of: date) { _, _ in
              Task { await reloadDay() }
            }
          Spacer(minLength: 0)
        }

        Text("Tap the date to view a different day.")
          .font(HP.Font.caption)
          .foregroundStyle(HP.Color.textMuted)

        if isLoading {
          HPLoadingState()
        }

      }
    }
  }

  private var programCard: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Strength program") {
          if scheduleContext?.isScheduled == true {
            ProgressRing(progress: progressFraction())
              .frame(width: 44, height: 44)
          }
        }

        if assignment != nil, let template {
          let ctx = scheduleContext
          Text("Program: \(template.name)")
            .font(HP.Font.callout)
            .foregroundStyle(HP.Color.textMuted)

          if ctx?.isScheduled == true, let w = ctx?.week, let d = ctx?.dayIndex {
            Text("Scheduled today • Week \(w) Day \(d)")
              .font(HP.Font.headline)
              .foregroundStyle(HP.Color.text)
            Text(progressSubtitle())
              .font(HP.Font.caption)
              .foregroundStyle(HP.Color.textMuted)
          } else if let next = ctx?.nextLiftDateISO {
            Text("Not scheduled today • Next lift day: \(next)")
              .font(HP.Font.headline)
              .foregroundStyle(HP.Color.text)
          } else {
            Text("No more scheduled lifts in this program.")
              .font(HP.Font.headline)
              .foregroundStyle(HP.Color.text)
          }
        } else {
          Text("No active program assigned yet.")
            .font(HP.Font.callout)
            .foregroundStyle(HP.Color.textMuted)
        }
      }
    }
  }

  private var strengthLoggerCard: some View {
    HPCard {
      DisclosureGroup(isExpanded: $isStrengthExpanded) {
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          if exercises.isEmpty {
            Text("No exercises scheduled for today.")
              .font(HP.Font.callout)
              .foregroundStyle(HP.Color.textMuted)
          } else {
            ForEach(scheduledExercises(), id: \.name) { ex in
              StrengthExerciseLogger(
                exercise: ex,
                weights: Binding(
                  get: { weightEntries[ex.name] ?? defaultWeights(for: ex) },
                  set: { weightEntries[ex.name] = $0 }
                ),
                noWeight: Binding(get: { noWeight[ex.name] ?? false },
                                  set: { noWeight[ex.name] = $0 }),
                setsCompleted: Binding(get: { setsCompleted[ex.name] ?? (ex.sets ?? 0) },
                                       set: { setsCompleted[ex.name] = $0 }),
                notes: Binding(get: { perExerciseNotes[ex.name] ?? "" },
                               set: { perExerciseNotes[ex.name] = $0 }),
                hasVideo: { setNumber in
                  programSetMedia[setVideoKey(exerciseName: ex.name, setNumber: setNumber)] != nil
                    || pendingSetVideoData[setVideoKey(exerciseName: ex.name, setNumber: setNumber)] != nil
                },
                onVideoSelected: { setNumber, item in
                  Task { await prepareSetVideo(item, exerciseName: ex.name, setNumber: setNumber) }
                }
              )
            }
          }
        }
        .padding(.top, HP.Space.sm)
      } label: {
        Text("Log today’s lifts")
          .font(HP.Font.headline)
          .foregroundStyle(HP.Color.text)
      }
      .tint(HP.Color.accent)
    }
  }

  private var improvementCard: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Improvement")
        if let latest = testingEntries.first {
          let prev = testingEntries.dropFirst().first
          ViewThatFits(in: .horizontal) {
            HStack(spacing: HP.Space.sm) {
              ImprovementTile(
                title: "Latest test",
                value: latest.entry_date,
                delta: nil
              )
              ImprovementTile(
                title: "Max EV",
                value: fmt(latest.max_exit_velo),
                delta: deltaText(latest.max_exit_velo, prev?.max_exit_velo, unit: "mph")
              )
            }
            VStack(spacing: HP.Space.sm) {
              ImprovementTile(title: "Latest test", value: latest.entry_date, delta: nil)
              ImprovementTile(
                title: "Max EV",
                value: fmt(latest.max_exit_velo),
                delta: deltaText(latest.max_exit_velo, prev?.max_exit_velo, unit: "mph")
              )
            }
          }
          ViewThatFits(in: .horizontal) {
            HStack(spacing: HP.Space.sm) {
              ImprovementTile(
                title: "Avg EV",
                value: fmt(latest.avg_exit_velo),
                delta: deltaText(latest.avg_exit_velo, prev?.avg_exit_velo, unit: "mph")
              )
              ImprovementTile(
                title: "Strength total",
                value: fmt(strengthTotal(latest)),
                delta: deltaText(strengthTotal(latest), prev.flatMap(strengthTotal), unit: "lb")
              )
            }
            VStack(spacing: HP.Space.sm) {
              ImprovementTile(
                title: "Avg EV",
                value: fmt(latest.avg_exit_velo),
                delta: deltaText(latest.avg_exit_velo, prev?.avg_exit_velo, unit: "mph")
              )
              ImprovementTile(
                title: "Strength total",
                value: fmt(strengthTotal(latest)),
                delta: deltaText(strengthTotal(latest), prev.flatMap(strengthTotal), unit: "lb")
              )
            }
          }
        } else {
          Text("Add your first Testing entry to see improvement trends.")
            .font(HP.Font.callout)
            .foregroundStyle(HP.Color.textMuted)
        }
      }
    }
  }

  private var submitCard: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPButton(title: "Save workout", variant: .primary, size: .lg,
                 isLoading: isSaving, fullWidth: true) {
          Task { await submitDay() }
        }

        Text("Save the sets, weights, custom results, and notes entered above.")
          .font(HP.Font.caption)
          .foregroundStyle(HP.Color.textMuted)
      }
    }
  }

  private var isDaySaved: Bool {
    if !strengthLogs.isEmpty { return true }
    return false
  }

  private func defaultWeights(for ex: SDExercise) -> [String] {
    let n = max(0, ex.sets ?? 0)
    return Array(repeating: "", count: n)
  }

  private func hydrateFromExistingLogs() {
    var weights: [String: [String]] = [:]
    var nw: [String: Bool] = [:]
    var sc: [String: Int] = [:]
    var notes: [String: String] = [:]
    for l in strengthLogs {
      nw[l.exercise_name] = l.no_weight
      if let w = l.set_weights_json { weights[l.exercise_name] = w }
      if let c = l.sets_completed { sc[l.exercise_name] = c }
      if let n = l.notes { notes[l.exercise_name] = n }
    }
    weightEntries = weights
    noWeight = nw
    setsCompleted = sc
    perExerciseNotes = notes
  }

  private func setVideoKey(exerciseName: String, setNumber: Int) -> String {
    "\(exerciseName)\u{1f}\(setNumber)"
  }

  private func prepareSetVideo(_ item: PhotosPickerItem, exerciseName: String, setNumber: Int) async {
    do {
      guard let data = try await item.loadTransferable(type: Data.self) else {
        errorText = "That set video could not be loaded."
        return
      }
      guard data.count <= 262_144_000 else {
        errorText = "Set videos must be 250 MB or smaller."
        return
      }
      let type = item.supportedContentTypes.first(where: { $0.conforms(to: .movie) }) ?? .quickTimeMovie
      pendingSetVideoData[setVideoKey(exerciseName: exerciseName, setNumber: setNumber)] = PendingProgramSetVideo(
        data: data,
        fileExtension: type.preferredFilenameExtension ?? "mov",
        mimeType: type.preferredMIMEType ?? "video/quicktime"
      )
    } catch {
      errorText = "That set video could not be prepared."
    }
  }

  private func reloadAll() async {
    await reloadTodayAggregate()
    await reloadAssignment()
    await reloadDay()
    await reloadTesting()
    await reloadBaseballDay()
  }

  private func reloadTodayAggregate() async {
    guard let supabase = appState.supabase, let organizationId = appState.activeOrgId else { return }
    let context = todayContextIdentity
    if todayPublishedContext != context { todayAggregate = nil }
    let token = UUID()
    todayLoadToken = token
    todayServiceError = nil
    do {
      let response = try await supabase.today(
        organizationId: organizationId,
        seasonId: appState.selectedSeason?.id,
        teamId: nil,
        date: date,
        contextToken: context
      )
      guard SDAsyncRequestGuard.accepts(
        responseContext: context,
        responseToken: token,
        activeContext: todayContextIdentity,
        currentToken: todayLoadToken,
        taskIsCancelled: Task.isCancelled
      ) else { return }
      guard response.context.organization_id == organizationId,
            response.context.role == .player else { return }
      todayAggregate = response
      todayPublishedContext = context
    } catch {
      guard SDAsyncRequestGuard.accepts(
        responseContext: context,
        responseToken: token,
        activeContext: todayContextIdentity,
        currentToken: todayLoadToken,
        taskIsCancelled: Task.isCancelled
      ) else { return }
      todayServiceError = SDApplicationErrorClassifier.alertMessage(for: error)
    }
  }

  private func reloadBaseballDay() async {
    guard let supabase = appState.supabase, let organizationId = appState.activeOrgId else { return }
    let context = todayContextIdentity
    do {
      let session = try await supabase.client.auth.session
      let playerId = session.user.id
      let start = DateUtils.startOfDayET(max(date, Date()))
      let end = DateUtils.calendarET.date(byAdding: .day, value: 90, to: start)!
      let upcomingEvents = try await supabase.listCanonicalEvents(
        organizationId: organizationId,
        from: start,
        through: end
      )
      .filter { ![.draft, .canceled].contains($0.status) && $0.scheduled_start >= start }
      .sorted { $0.scheduled_start < $1.scheduled_start }

      var loadedTeamEvents: [SDCanonicalEvent] = []
      if let nextTeamEvent = upcomingEvents.first {
        loadedTeamEvents.append(nextTeamEvent)
      }
      if let nextGame = upcomingEvents.first(where: { $0.event_type == .game }),
         !loadedTeamEvents.contains(where: { $0.id == nextGame.id }) {
        loadedTeamEvents.append(nextGame)
      }
      guard context == todayContextIdentity, !Task.isCancelled else { return }

      var loadedAttendance: [UUID: Bool] = [:]
      for event in loadedTeamEvents {
        guard context == todayContextIdentity, !Task.isCancelled else { return }
        if let response = try await supabase.listEventAttendance(
          eventId: event.id,
          organizationId: organizationId
        ).first(where: { $0.player_id == playerId }),
           let attending = response.expected_attendance {
          loadedAttendance[event.id] = attending
        }
      }
      guard context == todayContextIdentity, !Task.isCancelled else { return }
      teamEvents = loadedTeamEvents
      eventAttendance = loadedAttendance
    } catch {
      guard context == todayContextIdentity, !Task.isCancelled else { return }
      errorText = SDApplicationErrorClassifier.alertMessage(for: error)
    }
  }

  private func respondToEvent(_ event: SDCanonicalEvent, attending: Bool) {
    Task {
      guard let supabase = appState.supabase, let organizationId = appState.activeOrgId else { return }
      attendanceSavingEventIds.insert(event.id)
      defer { attendanceSavingEventIds.remove(event.id) }
      do {
        let playerId = try await supabase.client.auth.session.user.id
        _ = try await supabase.setExpectedGameAttendance(
          eventId: event.id,
          organizationId: organizationId,
          playerId: playerId,
          attending: attending
        )
        eventAttendance[event.id] = attending
        changingAttendanceEventIds.remove(event.id)
        success(attending ? "You’re marked as coming." : "You’re marked as not coming.")
      } catch {
        errorText = "Your response could not be saved. Please try again."
      }
    }
  }

  private func reloadAssignment() async {
    guard let supabase = appState.supabase else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      let session = try await supabase.client.auth.session
      let uid = session.user.id
      assignment = try await supabase.fetchActiveAssignment(playerId: uid)
      if let assignment {
        template = try await supabase.fetchTemplate(id: assignment.template_id)
      } else {
        template = nil
      }
    } catch {
      errorText = SDApplicationErrorClassifier.alertMessage(
        for: error,
        taskIsCancelled: Task.isCancelled
      )
    }
  }

  private func reloadDay() async {
    guard let supabase = appState.supabase else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      let session = try await supabase.client.auth.session
      let uid = session.user.id
      strengthLogs = try await supabase.fetchStrengthLogs(playerId: uid, dateISO: dateISO)
      if let assignment {
        let media = try await supabase.listProgramSetMedia(
          playerId: uid,
          assignmentId: assignment.id,
          dateISO: dateISO
        )
        programSetMedia = Dictionary(uniqueKeysWithValues: media.map {
          (setVideoKey(exerciseName: $0.exercise_name, setNumber: $0.set_number), $0)
        })
      } else {
        programSetMedia = [:]
      }
      pendingSetVideoData = [:]

      if let assignment, let template {
        let ctx = SDProgramSchedule.context(for: date, assignment: assignment, template: template)
        if ctx.isScheduled, let w = ctx.week, let d = ctx.dayIndex {
          let days = try await supabase.fetchProgramDays(templateId: template.id)
          exercises = (days.first(where: { $0.week == w && $0.day_index == d })?.exercises ?? [])
            .map { ex in
              var copy = ex
              copy.name = ex.name.trimmingCharacters(in: .whitespacesAndNewlines)
              copy.unit = ex.unit?.trimmingCharacters(in: .whitespacesAndNewlines)
              copy.reps = ex.reps?.trimmingCharacters(in: .whitespacesAndNewlines)
              copy.notes = ex.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
              return copy
            }
            .filter { !$0.name.isEmpty }
        } else {
          exercises = []
        }
      } else {
        exercises = []
      }
      if scheduleContext?.isScheduled == true {
        isStrengthExpanded = true
      }
      hydrateFromExistingLogs()
    } catch {
      errorText = SDApplicationErrorClassifier.alertMessage(
        for: error,
        taskIsCancelled: Task.isCancelled
      )
    }
  }

  private func reloadTesting() async {
    guard let supabase = appState.supabase else { return }
    do {
      let session = try await supabase.client.auth.session
      let uid = session.user.id
      let rows = try await supabase.listTestingEntries(playerId: uid)
      testingEntries = rows.sorted { $0.entry_date > $1.entry_date }
    } catch {
      // Non-fatal; Today can render without this.
    }
  }

  private func submitDay() async {
    guard let supabase = appState.supabase else { return }
    isSaving = true
    defer { isSaving = false }
    do {
      let session = try await supabase.client.auth.session
      let uid = session.user.id

      if let assignment, let template, let ctx = scheduleContext, ctx.isScheduled, let week = ctx.week, let dayIndex = ctx.dayIndex {
        for ex in scheduledExercises() {
          let name = ex.name.trimmingCharacters(in: .whitespacesAndNewlines)
          if name.isEmpty { continue }

          let nw = noWeight[name] ?? false
          let note = perExerciseNotes[name]?.trimmingCharacters(in: .whitespacesAndNewlines)
          let hasPendingVideo = pendingSetVideoData.keys.contains { $0.hasPrefix("\(name)\u{1f}") }
          if nw {
            let completed = max(0, setsCompleted[name] ?? 0)
            if completed == 0 && (note ?? "").isEmpty && !hasPendingVideo { continue }
            _ = try await supabase.upsertStrengthLog(
              playerId: uid,
              dateISO: dateISO,
              assignmentId: assignment.id,
              templateId: template.id,
              week: week,
              dayIndex: dayIndex,
              exerciseName: name,
              noWeight: true,
              setWeights: nil,
              setsCompleted: max(completed, hasPendingVideo ? 1 : 0),
              notes: (note ?? "").isEmpty ? nil : note,
              orgId: appState.activeOrgId
            )
          } else {
            let weights = (weightEntries[name] ?? defaultWeights(for: ex)).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            let nonEmptyCount = weights.filter { !$0.isEmpty }.count
            if nonEmptyCount == 0 && (note ?? "").isEmpty && !hasPendingVideo { continue }
            _ = try await supabase.upsertStrengthLog(
              playerId: uid,
              dateISO: dateISO,
              assignmentId: assignment.id,
              templateId: template.id,
              week: week,
              dayIndex: dayIndex,
              exerciseName: name,
              noWeight: false,
              setWeights: nonEmptyCount == 0 ? nil : weights,
              setsCompleted: max(nonEmptyCount, hasPendingVideo ? 1 : 0),
              notes: (note ?? "").isEmpty ? nil : note,
              orgId: appState.activeOrgId
            )
          }
        }
        if let organizationId = appState.activeOrgId {
          for (key, pendingVideo) in pendingSetVideoData {
            let parts = key.components(separatedBy: "\u{1f}")
            guard parts.count == 2, let setNumber = Int(parts[1]) else { continue }
            let exerciseName = parts[0]
            let path = try await supabase.uploadProgramSetVideo(
              pendingVideo.data,
              organizationId: organizationId,
              playerId: uid,
              assignmentId: assignment.id,
              dateISO: dateISO,
              fileExtension: pendingVideo.fileExtension,
              contentType: pendingVideo.mimeType
            )
            _ = try await supabase.upsertProgramSetMedia(SDProgramSetMediaWrite(
              org_id: organizationId,
              player_id: uid,
              assignment_id: assignment.id,
              template_id: template.id,
              log_date: dateISO,
              exercise_name: exerciseName,
              set_number: setNumber,
              storage_path: path,
              file_name: "Set-\(setNumber).\(pendingVideo.fileExtension)",
              mime_type: pendingVideo.mimeType,
              byte_size: pendingVideo.data.count,
              uploaded_by: uid
            ))
          }
          pendingSetVideoData = [:]
        }
      }

      await reloadDay()
      success("Saved.")
    } catch {
      errorText = SDApplicationErrorClassifier.alertMessage(
        for: error,
        taskIsCancelled: Task.isCancelled
      )
    }
  }

  private func scheduledExercises() -> [SDExercise] {
    exercises
      .filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
  }

  private func progressFraction() -> Double {
    guard scheduleContext?.isScheduled == true else { return 0 }
    let scheduled = scheduledExercises()
    if scheduled.isEmpty { return 0 }
    let logged = scheduled.filter { isExerciseLogged($0) }.count
    return Double(logged) / Double(scheduled.count)
  }

  private func progressSubtitle() -> String {
    let scheduled = scheduledExercises()
    if scheduled.isEmpty { return "No exercises scheduled." }
    let logged = scheduled.filter { isExerciseLogged($0) }.count
    return "\(logged) / \(scheduled.count) exercises logged"
  }

  private func isExerciseLogged(_ ex: SDExercise) -> Bool {
    let name = ex.name.trimmingCharacters(in: .whitespacesAndNewlines)
    if name.isEmpty { return false }
    let requiredSets = max(0, ex.sets ?? 0)
    if noWeight[name] == true {
      let done = setsCompleted[name] ?? 0
      return requiredSets == 0 ? (done > 0) : (done >= requiredSets)
    }
    let weights = (weightEntries[name] ?? defaultWeights(for: ex)).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    let nonEmpty = weights.filter { !$0.isEmpty }.count
    return requiredSets == 0 ? (nonEmpty > 0) : (nonEmpty >= requiredSets)
  }

  private func strengthTotal(_ e: SDTestingEntry) -> Double? {
    let parts = [e.squat_1rm, e.bench_1rm, e.deadlift_1rm].compactMap { $0 }
    guard !parts.isEmpty else { return nil }
    return parts.reduce(0, +)
  }

  private func fmt(_ v: Double?) -> String {
    guard let v else { return "—" }
    if v.rounded() == v { return String(Int(v)) }
    return String(format: "%.1f", v)
  }

  private func deltaText(_ a: Double?, _ b: Double?, unit: String) -> String? {
    guard let a, let b else { return nil }
    let d = a - b
    if abs(d) < 0.0001 { return "0 \(unit)" }
    let sign = d >= 0 ? "+" : "−"
    let mag = abs(d)
    let v = (mag.rounded() == mag) ? String(Int(mag)) : String(format: "%.1f", mag)
    return "\(sign)\(v) \(unit)"
  }

  private func success(_ text: String) {
    withAnimation { successToast = text }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
      withAnimation { successToast = nil }
    }
  }
}

/// Reskinned completion ring — wraps `HPProgressIndicator(.ring)`.
/// Preserves the `progress` (0...1) input from `progressFraction()`.
struct ProgressRing: View {
  let progress: Double // 0..1

  var body: some View {
    HPProgressIndicator(value: min(1, max(0, progress)), style: .ring, lineWidth: 6)
      .environment(\.dynamicTypeSize, .large)
      .accessibilityValue("\(Int((min(1, max(0, progress)) * 100).rounded())) percent")
  }
}

/// Reskinned improvement metric — wraps `HPMetricCard` (context over raw
/// number). Preserves the `title` / `value` / `delta` inputs; the trend arrow
/// is derived from the preformatted delta's sign.
struct ImprovementTile: View {
  let title: String
  let value: String
  let delta: String?

  var body: some View {
    HPMetricCard(
      title: title,
      value: value,
      delta: (delta?.isEmpty == false) ? delta : nil,
      trend: trend
    )
  }

  private var trend: HPTrendDirection? {
    guard let delta, !delta.isEmpty else { return nil }
    if delta.hasPrefix("+") { return .up }
    if delta.hasPrefix("−") || delta.hasPrefix("-") { return .down }
    return .flat
  }
}

/// Reskinned per-exercise strength logger. Presentation only — the four
/// `@Binding`s (`weights`, `noWeight`, `setsCompleted`, `notes`) are preserved
/// exactly; they persist via `submitDay()`.
struct StrengthExerciseLogger: View {
  let exercise: SDExercise
  @Binding var weights: [String]
  @Binding var noWeight: Bool
  @Binding var setsCompleted: Int
  @Binding var notes: String
  let hasVideo: (Int) -> Bool
  let onVideoSelected: (Int, PhotosPickerItem) -> Void

  var body: some View {
    HPCard(style: .flat) {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        VStack(alignment: .leading, spacing: 2) {
          Text(exercise.name)
            .font(HP.Font.headline)
            .foregroundStyle(HP.Color.text)
          Text(programLine(exercise))
            .font(HP.Font.caption)
            .foregroundStyle(HP.Color.textMuted)
        }

        if let coachInstructions = exercise.notes?.trimmingCharacters(in: .whitespacesAndNewlines),
           !coachInstructions.isEmpty {
          VStack(alignment: .leading, spacing: 4) {
            Text("Coach instructions")
              .font(HP.Font.eyebrow)
              .tracking(HP.Font.eyebrowTracking)
              .foregroundStyle(HP.Color.accent)
            Text(coachInstructions)
              .font(HP.Font.callout)
              .foregroundStyle(HP.Color.text)
              .fixedSize(horizontal: false, vertical: true)
          }
          .padding(HP.Space.sm)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(HP.Color.surfaceRaised, in: RoundedRectangle(cornerRadius: HP.Radius.md, style: .continuous))
        }

        VStack(alignment: .leading, spacing: 2) {
          Toggle("No weight", isOn: $noWeight)
            .font(HP.Font.callout)
            .foregroundStyle(HP.Color.text)
            .tint(HP.Color.accent)
          Text("Use for bodyweight, jumps, or other unweighted work.")
            .font(HP.Font.caption)
            .foregroundStyle(HP.Color.textMuted)
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)

        if noWeight {
          Stepper(value: $setsCompleted, in: 0...50) {
            Text("Sets completed: \(setsCompleted)")
              .font(HP.Font.callout)
              .foregroundStyle(HP.Color.text)
          }
          ForEach(1...max(1, exercise.sets ?? setsCompleted), id: \.self) { setNumber in
            ProgramSetVideoPicker(
              setNumber: setNumber,
              hasVideo: hasVideo(setNumber),
              onVideoSelected: onVideoSelected
            )
          }
        } else {
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            ForEach(Array(weights.indices), id: \.self) { idx in
              SetInputWithVideo(
                setNumber: idx + 1,
                weight: Binding(
                  get: { weights[idx] },
                  set: { weights[idx] = $0 }
                ),
                hasVideo: hasVideo(idx + 1),
                onVideoSelected: onVideoSelected
              )
            }
            ViewThatFits(in: .horizontal) {
              HStack(spacing: HP.Space.sm) {
                HPButton(title: "Add set", systemImage: "plus", variant: .secondary, size: .sm) {
                  weights.append("")
                }
                HPButton(title: "Remove set", systemImage: "minus", variant: .secondary, size: .sm) {
                  if !weights.isEmpty { weights.removeLast() }
                }
                .disabled(weights.isEmpty)
              }
              .fixedSize(horizontal: true, vertical: false)

              VStack(spacing: HP.Space.xs) {
                HPButton(title: "Add set", systemImage: "plus", variant: .secondary, size: .sm, fullWidth: true) {
                  weights.append("")
                }
                .fixedSize(horizontal: false, vertical: true)
                HPButton(title: "Remove set", systemImage: "minus", variant: .secondary, size: .sm, fullWidth: true) {
                  if !weights.isEmpty { weights.removeLast() }
                }
                .disabled(weights.isEmpty)
                .fixedSize(horizontal: false, vertical: true)
              }
              .fixedSize(horizontal: false, vertical: true)
            }
          }
        }

        HPFormField(label: "Notes (optional)", text: $notes, kind: .multiline, placeholder: "Optional")
      }
    }
  }

  private func programLine(_ ex: SDExercise) -> String {
    let s = ex.sets.map(String.init) ?? "—"
    let r = (ex.reps ?? "—").isEmpty ? "—" : (ex.reps ?? "—")
    let u = (ex.unit ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if u.isEmpty {
      return "\(s) x \(r)"
    }
    return "\(s) x \(r) • \(u)"
  }
}

private struct SetInputWithVideo: View {
  let setNumber: Int
  @Binding var weight: String
  let hasVideo: Bool
  let onVideoSelected: (Int, PhotosPickerItem) -> Void
  @State private var item: PhotosPickerItem?

  var body: some View {
    VStack(alignment: .leading, spacing: HP.Space.xs) {
      HPFormField(label: "Set \(setNumber) weight", text: $weight, placeholder: "Weight")
      PhotosPicker(selection: $item, matching: .videos) {
        Label(hasVideo ? "Video attached" : "Add set video", systemImage: hasVideo ? "checkmark.circle.fill" : "video.badge.plus")
          .font(HP.Font.caption.weight(.semibold))
          .foregroundStyle(hasVideo ? HP.Color.success : HP.Color.accent)
          .frame(minHeight: 36)
      }
      .onChange(of: item) { _, selected in
        guard let selected else { return }
        onVideoSelected(setNumber, selected)
      }
    }
  }
}

private struct ProgramSetVideoPicker: View {
  let setNumber: Int
  let hasVideo: Bool
  let onVideoSelected: (Int, PhotosPickerItem) -> Void
  @State private var item: PhotosPickerItem?

  var body: some View {
    PhotosPicker(selection: $item, matching: .videos) {
      Label(
        hasVideo ? "Set \(setNumber) video attached" : "Add set \(setNumber) video",
        systemImage: hasVideo ? "checkmark.circle.fill" : "video.badge.plus"
      )
      .font(HP.Font.caption.weight(.semibold))
      .foregroundStyle(hasVideo ? HP.Color.success : HP.Color.accent)
      .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
    }
    .onChange(of: item) { _, selected in
      guard let selected else { return }
      onVideoSelected(setNumber, selected)
    }
  }
}
