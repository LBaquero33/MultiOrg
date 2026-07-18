import SwiftUI

struct SDPlayerTodayView: View {
  var body: some View {
    NavigationStack {
      SDPlayerTodayViewInternal(initialDate: Date())
    }
  }
}

private struct PlayerAvailabilityPresentation: Identifiable {
  let id = UUID()
  let event: SDTeamEvent
  let draft: SDEventAvailabilityDraft
}

private struct PlayerPendingAvailability {
  let event: SDTeamEvent
  let draft: SDEventAvailabilityDraft
  let requestId: UUID
}

struct SDPlayerTodayViewInternal: View {
  @EnvironmentObject private var appState: AppState

  let initialDate: Date
  @State private var date: Date
  @State private var assignment: SDProgramAssignment?
  @State private var template: SDProgramTemplate?
  @State private var exercises: [SDExercise] = []
  @State private var strengthLogs: [SDStrengthLog] = []
  @State private var dailyLog: SDDailyLog?
  @State private var testingEntries: [SDTestingEntry] = []
  @State private var teamEvents: [SDTeamEvent] = []
  @State private var eventOperations: [UUID: SDEventOperationDetailResponse] = [:]
  @State private var practicePlans: [UUID: SDPracticePlanDetailResponse] = [:]
  @State private var gamePlans: [UUID: SDGamePlanDetailResponse] = [:]
  @State private var availabilityEditor: PlayerAvailabilityPresentation?
  @State private var pendingAvailability: PlayerPendingAvailability?

  @State private var comments = ""
  @State private var feel = 5
  @State private var gotVideo = false
  @State private var ateBreakfast = false
  @State private var hitDailyGoals = false
  @State private var stuckToProcess = false
  @State private var fellShort = ""
  @State private var excelled = ""

  @State private var weightEntries: [String: [String]] = [:]
  @State private var noWeight: [String: Bool] = [:]
  @State private var setsCompleted: [String: Int] = [:]
  @State private var perExerciseNotes: [String: String] = [:]

  @State private var isLoading = false
  @State private var isSaving = false
  @State private var errorText: String?
  @State private var successToast: String?

  @State private var isStrengthExpanded = true
  @State private var isSelfAssessmentExpanded = false

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
      playerBaseballDayCard
      RegistrationFamilySummaryCard(audience: .player)
      improvementCard
      programCard
    } activities: {
      if scheduleContext?.isScheduled == true {
        strengthLoggerCard
      }
    } subActivities: {
      SDPlayerBPDaySection(date: date)
    } assessment: {
      selfAssessmentCard
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
    .sheet(item: $availabilityEditor) { presentation in
      EventAvailabilityEditorSheet(
        playerName: appState.myProfile?.displayName ?? "Player",
        initial: presentation.draft
      ) { draft, requestId in
        availabilityEditor = nil
        saveAvailability(event: presentation.event, draft: draft, requestId: requestId)
      }
    }
    .task(id: todayContextIdentity) {
      await reloadAll()
    }
  }

  private var dateISO: String { DateUtils.toISODate(date) }
  private var todayContextIdentity: String {
    "\(appState.myProfile?.id.uuidString ?? "none"):\(appState.activeOrgId?.uuidString ?? "none"):\(dateISO)"
  }

  private var playerBaseballDayCard: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Baseball mission") {
          HPStatusBadge(text: "\(teamEvents.count) today", kind: teamEvents.isEmpty ? .neutral : .info)
        }
        if teamEvents.isEmpty {
          HPEmptyState(title: "No team event", message: "No visible team mission is scheduled for this day.", systemImage: "calendar")
        } else {
          ForEach(teamEvents) { event in
            let detail = eventOperations[event.id]
            let participant = detail?.participants?.first
            VStack(alignment: .leading, spacing: HP.Space.xs) {
              HStack {
                Label(event.title, systemImage: event.event_type.systemImage)
                  .font(HP.Font.headline).foregroundStyle(HP.Color.text)
                Spacer()
                HPStatusBadge(text: detail?.operation?.status.label ?? "Not Started", kind: detail?.operation?.status == .completed ? .success : .info)
              }
              Text("\(event.team_name ?? "Team") • \(event.event_type.label) • \(event.startDate.formatted(date: .omitted, time: .shortened))")
                .font(HP.Font.callout).foregroundStyle(HP.Color.textMuted)
              if let arrival = event.arrivalDate {
                Label("Arrive \(arrival.formatted(date: .omitted, time: .shortened))", systemImage: "figure.walk.arrival")
              }
              if let location = event.location_name?.sdNilIfBlank { Label(location, systemImage: "mappin") }
              if let attire = event.uniformOrDressCode?.sdNilIfBlank { Label(attire, systemImage: "tshirt") }
              Text("Availability: \(participant?.availability_status.label ?? "Unknown")")
                .font(HP.Font.callout.weight(.semibold)).foregroundStyle(HP.Color.text)
              if event.status == .cancelled {
                Label(event.cancellation_reason ?? "Event cancelled", systemImage: "calendar.badge.exclamationmark")
                  .foregroundStyle(HP.Color.warning)
              } else if event.status == .postponed {
                Label("Event postponed", systemImage: "clock.badge.exclamationmark")
                  .foregroundStyle(HP.Color.warning)
              }
              Button("Update Availability") {
                availabilityEditor = PlayerAvailabilityPresentation(
                  event: event,
                  draft: availabilityDraft(participant)
                )
              }
              .buttonStyle(.bordered).frame(minHeight: 44)
              .disabled(
                detail?.operation?.status == .completed ||
                  [.completed, .cancelled, .postponed].contains(event.status)
              )
              ForEach(detail?.notes ?? []) { note in
                if note.visibility == "team" || note.subject_player_id == appState.myProfile?.id {
                  Text(note.body).font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
                }
              }
              if event.event_type == .practice, let practice = practicePlans[event.id], let plan = practice.plan {
                VStack(alignment: .leading, spacing: HP.Space.xs) {
                  Text("Practice: \(plan.title)").font(HP.Font.callout.weight(.semibold))
                  if !plan.objectives.isEmpty { Text(plan.objectives.joined(separator: " • ")) }
                  ForEach(practice.groups) { group in Text("Your group: \(group.name)") }
                  ForEach(practice.blocks.filter { $0.visibility != "staff_only" }) { block in
                    Text("\(block.title) • \(block.duration_minutes)m")
                  }
                  ForEach(practice.equipment.filter { $0.visibility == "player_visible" }) { item in
                    Label("Bring \(item.quantity)× \(item.name)", systemImage: "shippingbox")
                  }
                }
                .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
              }
              if event.event_type == .game, let game = gamePlans[event.id], let plan = game.plan {
                VStack(alignment: .leading, spacing: 4) {
                  Text("Game plan: \(plan.status.label) • \(plan.lineup_mode.label)")
                    .font(HP.Font.caption.weight(.semibold)).foregroundStyle(HP.Color.textMuted)
                  ForEach(game.batting_order ?? []) { entry in
                    Text("Your batting assignment: \(entry.batting_slot.map { "#\($0)" } ?? "Bench") • \(entry.offensive_role.label)")
                  }
                  ForEach(game.defense ?? []) { assignment in
                    Text("\(assignment.inning_number == 0 ? "Starting defense" : "Inning \(assignment.inning_number)"): \(assignment.position_label?.sdNilIfBlank ?? assignment.position_code)")
                  }
                  ForEach(game.pitcher_catcher ?? []) { assignment in
                    Text(assignment.role_type.replacingOccurrences(of: "_", with: " ").capitalized)
                  }
                  if let result = game.result {
                    Text(result.team_score.flatMap { team in result.opponent_score.map { "Final: \(team)–\($0)" } } ?? "Game completed")
                  }
                  ForEach(game.recaps ?? []) { recap in Text(recap.body) }
                }
                .font(HP.Font.caption).foregroundStyle(HP.Color.text)
              }
              if detail?.operation?.status == .completed, detail?.notes?.contains(where: { $0.note_type == "post_event_recap" }) != true {
                Text("Event complete. No visible recap has been published.")
                  .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
              }
            }
            .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
            if event.id != teamEvents.last?.id { Divider() }
          }
        }
        if let pendingAvailability {
          VStack(alignment: .leading, spacing: HP.Space.xs) {
            Text("Availability update awaiting confirmation.")
              .font(HP.Font.caption).foregroundStyle(HP.Color.warning)
            Button("Retry Availability") {
              saveAvailability(event: pendingAvailability.event, draft: pendingAvailability.draft, requestId: pendingAvailability.requestId)
            }
            .buttonStyle(.bordered)
          }
        }
      }
    }
  }

  private func availabilityDraft(_ participant: SDEventOperationParticipant?) -> SDEventAvailabilityDraft {
    SDEventAvailabilityDraft(
      status: participant?.availability_status ?? .unknown,
      reason: participant?.availability_reason ?? "",
      expectedArrival: SDEventOperationDateParser.date(participant?.expected_arrival_at),
      expectedDeparture: SDEventOperationDateParser.date(participant?.expected_departure_at)
    )
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

        if (appState.myProfile?.isCoach == false) {
          HPButton(title: "Enable Coach Mode (allowlist)", variant: .secondary, size: .sm) {
            Task { await appState.promoteMeToCoach() }
          }
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
                               set: { perExerciseNotes[ex.name] = $0 })
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

  private var selfAssessmentCard: some View {
    HPCard {
      DisclosureGroup(isExpanded: $isSelfAssessmentExpanded) {
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          Toggle("Did I get video today?", isOn: $gotVideo)
          Toggle("Did I eat breakfast?", isOn: $ateBreakfast)
          Toggle("Did I hit my daily goals?", isOn: $hitDailyGoals)
          Toggle("Did I stick to my process?", isOn: $stuckToProcess)

          HPFormField(label: "Where did I fall short? (optional)", text: $fellShort,
                      kind: .multiline, placeholder: "Optional")
          HPFormField(label: "How did I excel? (optional)", text: $excelled,
                      kind: .multiline, placeholder: "Optional")

          if scheduleContext?.isScheduled == true {
            HPFormField(label: "Comments (optional)", text: $comments,
                        kind: .multiline, placeholder: "Optional")
            VStack(alignment: .leading, spacing: 6) {
              Text("How did you feel? (\(feel))")
                .font(HP.Font.caption.weight(.semibold))
                .foregroundStyle(HP.Color.textMuted)
              Slider(value: Binding(get: { Double(feel) }, set: { feel = Int($0.rounded()) }), in: 1...10, step: 1)
                .tint(HP.Color.accent)
            }
          }
        }
        .font(HP.Font.callout)
        .foregroundStyle(HP.Color.text)
        .tint(HP.Color.accent)
        .padding(.top, HP.Space.sm)
      } label: {
        Text("Self assessment")
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
        HPButton(title: "Submit day", variant: .primary, size: .lg,
                 isLoading: isSaving, fullWidth: true) {
          Task { await submitDay() }
        }

        if scheduleContext?.isScheduled == true {
          Text("Submitting saves your self assessment and any lift logs for today.")
            .font(HP.Font.caption)
            .foregroundStyle(HP.Color.textMuted)
        } else {
          Text("Submitting saves your self assessment for today.")
            .font(HP.Font.caption)
            .foregroundStyle(HP.Color.textMuted)
        }
      }
    }
  }

  private var isDaySaved: Bool {
    if dailyLog != nil { return true }
    if !strengthLogs.isEmpty { return true }
    return false
  }

  private func defaultWeights(for ex: SDExercise) -> [String] {
    let n = max(0, ex.sets ?? 0)
    return Array(repeating: "", count: n)
  }

  private func hydrateFromExistingLogs() {
    comments = dailyLog?.comments ?? ""
    feel = dailyLog?.feel ?? 5
    gotVideo = dailyLog?.got_video ?? false
    ateBreakfast = dailyLog?.ate_breakfast ?? false
    hitDailyGoals = dailyLog?.hit_daily_goals ?? false
    stuckToProcess = dailyLog?.stuck_to_process ?? false
    fellShort = dailyLog?.fell_short ?? ""
    excelled = dailyLog?.excelled ?? ""

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

  private func reloadAll() async {
    await reloadAssignment()
    await reloadDay()
    await reloadTesting()
    await reloadBaseballDay()
  }

  private func reloadBaseballDay() async {
    guard let supabase = appState.supabase, let organizationId = appState.activeOrgId else { return }
    let context = todayContextIdentity
    do {
      let session = try await supabase.client.auth.session
      let playerId = session.user.id
      let start = DateUtils.startOfDayET(date)
      let end = DateUtils.calendarET.date(byAdding: .day, value: 1, to: start)!
      let loadedTeamEvents = try await supabase.listTeamEvents(
        organizationId: organizationId,
        teamId: nil,
        playerId: playerId,
        rangeStart: start,
        rangeEnd: end
      ).filter { $0.status != .draft }
      guard context == todayContextIdentity, !Task.isCancelled else { return }
      var details: [UUID: SDEventOperationDetailResponse] = [:]
      var plans: [UUID: SDPracticePlanDetailResponse] = [:]
      var games: [UUID: SDGamePlanDetailResponse] = [:]
      for event in loadedTeamEvents {
        guard context == todayContextIdentity, !Task.isCancelled else { return }
        do {
          details[event.id] = try await supabase.eventOperation(
            organizationId: organizationId,
            eventId: event.id,
            playerId: playerId
          )
        } catch {
          // A canonical event can truthfully exist before its day-operation row.
          // Keep the mission visible so the first availability declaration can
          // initialize the operation deterministically on the server.
          details[event.id] = SDEventOperationDetailResponse(
            ok: true,
            operation: nil,
            participants: [],
            checklist: [],
            notes: [],
            initialized: nil,
            replayed: nil
          )
        }
        if event.event_type == .practice {
          plans[event.id] = try? await supabase.practicePlan(
            organizationId: organizationId,
            eventId: event.id,
            playerId: playerId
          )
        }
        if event.event_type == .game {
          games[event.id] = try? await supabase.gamePlan(
            organizationId: organizationId,
            eventId: event.id,
            playerId: playerId
          )
        }
      }
      guard context == todayContextIdentity, !Task.isCancelled else { return }
      teamEvents = loadedTeamEvents
      eventOperations = details
      practicePlans = plans
      gamePlans = games
    } catch {
      guard context == todayContextIdentity, !Task.isCancelled else { return }
      eventOperations = [:]
      practicePlans = [:]
      gamePlans = [:]
      errorText = SDApplicationErrorClassifier.alertMessage(for: error)
    }
  }

  private func saveAvailability(event: SDTeamEvent, draft: SDEventAvailabilityDraft, requestId: UUID) {
    Task {
      guard let supabase = appState.supabase, let organizationId = appState.activeOrgId else { return }
      do {
        let playerId = try await supabase.client.auth.session.user.id
        let participant = eventOperations[event.id]?.participants?.first
        _ = try await supabase.updateEventAvailability(
          organizationId: organizationId,
          eventId: event.id,
          playerId: playerId,
          participantVersion: participant?.version,
          draft: draft,
          requestId: requestId
        )
        pendingAvailability = nil
        await reloadBaseballDay()
        success("Availability saved.")
      } catch {
        pendingAvailability = PlayerPendingAvailability(event: event, draft: draft, requestId: requestId)
        errorText = "Availability was not confirmed. The change remains available to retry."
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
      dailyLog = try await supabase.fetchDailyLog(playerId: uid, dateISO: dateISO)
      strengthLogs = try await supabase.fetchStrengthLogs(playerId: uid, dateISO: dateISO)

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

  private func upsertDailyLogOnly() async throws {
    guard let supabase = appState.supabase else { return }
    let session = try await supabase.client.auth.session
    let uid = session.user.id
    var payload: [String: AnyEncodable] = [
      "got_video": AnyEncodable(gotVideo),
      "ate_breakfast": AnyEncodable(ateBreakfast),
      "hit_daily_goals": AnyEncodable(hitDailyGoals),
      "stuck_to_process": AnyEncodable(stuckToProcess),
      "fell_short": AnyEncodable(fellShort.trimmingCharacters(in: .whitespacesAndNewlines)),
      "excelled": AnyEncodable(excelled.trimmingCharacters(in: .whitespacesAndNewlines)),
    ]
    if scheduleContext?.isScheduled == true {
      payload["comments"] = AnyEncodable(comments.trimmingCharacters(in: .whitespacesAndNewlines))
      payload["feel"] = AnyEncodable(feel)
    }
    dailyLog = try await supabase.upsertDailyLog(playerId: uid, dateISO: dateISO, payload: payload, orgId: appState.activeOrgId)
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
          if nw {
            let completed = max(0, setsCompleted[name] ?? 0)
            if completed == 0 && (note ?? "").isEmpty { continue }
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
              setsCompleted: completed,
              notes: (note ?? "").isEmpty ? nil : note,
              orgId: appState.activeOrgId
            )
          } else {
            let weights = (weightEntries[name] ?? defaultWeights(for: ex)).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            let nonEmptyCount = weights.filter { !$0.isEmpty }.count
            if nonEmptyCount == 0 && (note ?? "").isEmpty { continue }
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
              setsCompleted: nonEmptyCount,
              notes: (note ?? "").isEmpty ? nil : note,
              orgId: appState.activeOrgId
            )
          }
        }
      }

      try await upsertDailyLogOnly()
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
        } else {
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            ForEach(Array(weights.indices), id: \.self) { idx in
              HPFormField(
                label: "Set \(idx + 1) weight",
                text: Binding(
                  get: { weights[idx] },
                  set: { weights[idx] = $0 }
                ),
                placeholder: "Weight"
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
