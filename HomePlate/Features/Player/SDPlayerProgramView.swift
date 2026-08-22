import SwiftUI

struct SDPlayerProgramView: View {
  @EnvironmentObject private var appState: AppState

  @State private var programs: [PlayerProgramRecord] = []
  @State private var selectedProgramId: UUID?
  @State private var days: [SDProgramDay] = []
  @State private var selectedWeek = 1
  @State private var selectedDay = 1
  @State private var logTarget: PlayerProgramLogTarget?
  @State private var isLoading = false
  @State private var errorText: String?

  private var selectedProgram: PlayerProgramRecord? {
    guard let selectedProgramId else { return nil }
    return programs.first { $0.id == selectedProgramId }
  }

  private var availableWeeks: [Int] {
    guard let program = selectedProgram else { return [1] }
    let configured = Array(1...max(1, program.template.weeks))
    return Array(Set(configured + days.map(\.week))).sorted()
  }

  private var availableDays: [Int] {
    let configuredDays = days.filter { $0.week == selectedWeek }.map(\.day_index)
    if !configuredDays.isEmpty { return Array(Set(configuredDays)).sorted() }
    let fallbackCount = max(1, selectedProgram?.template.lift_weekdays.count ?? 1)
    return Array(1...fallbackCount)
  }

  private var selectedProgramDay: SDProgramDay? {
    days.first { $0.week == selectedWeek && $0.day_index == selectedDay }
  }

  var body: some View {
    NavigationStack {
      HPDetailScreenLayout {
        HPWorkspaceHeader(
          "Programs",
          context: selectedProgram.map { "\($0.template.kind.title) • \($0.template.name)" }
            ?? "Your assigned development plans"
        )
      } metrics: {
        EmptyView()
      } details: {
        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.md) {
            HPSectionHeader("Assigned programs") {
              if !programs.isEmpty {
                HPStatusBadge(text: "\(programs.filter(\.isActive).count) active", kind: .success)
              }
            }

            if isLoading && programs.isEmpty {
              HPLoadingState(text: "Loading programs…")
            } else if programs.isEmpty {
              HPEmptyState(
                title: "No programs assigned",
                message: "Your coach can assign S&C, hitting, and pitching programs here.",
                systemImage: "figure.strengthtraining.traditional"
              )
            } else {
              Picker("Program", selection: $selectedProgramId) {
                ForEach(programs) { program in
                  Text(program.pickerLabel).tag(Optional(program.id))
                }
              }
              .pickerStyle(.menu)
              .tint(HP.Color.accent)

              if let program = selectedProgram {
                VStack(alignment: .leading, spacing: HP.Space.xs) {
                  HStack(alignment: .top, spacing: HP.Space.sm) {
                    Label(program.template.name, systemImage: program.template.kind.systemImage)
                      .font(HP.Font.headline)
                      .foregroundStyle(HP.Color.text)
                      .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: HP.Space.sm)
                    HPStatusBadge(
                      text: program.isActive ? "Active" : "Ended",
                      kind: program.isActive ? .success : .neutral
                    )
                  }
                  Text(program.detailLine)
                    .font(HP.Font.caption)
                    .foregroundStyle(HP.Color.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Divider().overlay(HP.Color.border)
                HPSectionHeader("Program schedule")
                HStack(spacing: HP.Space.sm) {
                  Picker("Week", selection: $selectedWeek) {
                    ForEach(availableWeeks, id: \.self) { Text("Week \($0)").tag($0) }
                  }
                  .pickerStyle(.menu)
                  .tint(HP.Color.accent)

                  Picker("Day", selection: $selectedDay) {
                    ForEach(availableDays, id: \.self) { Text("Day \($0)").tag($0) }
                  }
                  .pickerStyle(.menu)
                  .tint(HP.Color.accent)
                }
              }
            }
          }
        }
      } related: { _ in
        if let program = selectedProgram {
          HPCard {
            VStack(alignment: .leading, spacing: HP.Space.sm) {
              HPSectionHeader(program.template.kind == .strength ? "Exercises" : "Drills") {
                HPStatusBadge(text: "Week \(selectedWeek) • Day \(selectedDay)", kind: .neutral)
              }
              let exercises = selectedProgramDay?.exercises ?? []
              if exercises.isEmpty {
                HPEmptyState(
                  title: "No items for this day",
                  message: "This assigned program day does not contain any exercises yet.",
                  systemImage: program.template.kind.systemImage
                )
              } else {
                ForEach(exercises, id: \.id) { exercise in
                  HPCard(style: .flat) {
                    VStack(alignment: .leading, spacing: 3) {
                      Text(exercise.name)
                        .font(HP.Font.headline)
                        .foregroundStyle(HP.Color.text)
                      Text(line(exercise))
                        .font(HP.Font.caption)
                        .foregroundStyle(HP.Color.textMuted)
                      if let notes = exercise.notes, !notes.isEmpty {
                        Text(notes)
                          .font(HP.Font.caption)
                          .foregroundStyle(HP.Color.textMuted)
                          .fixedSize(horizontal: false, vertical: true)
                      }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                  }
                }
              }
            }
          }
        }
      } primaryAction: {
        if let program = selectedProgram,
           program.isActive,
           let scheduledDate = SDProgramSchedule.scheduledDate(
             week: selectedWeek,
             dayIndex: selectedDay,
             assignment: program.assignment,
             template: program.template
           ) {
          HPCard {
            HPButton(
              title: "Open and log this day",
              systemImage: "square.and.pencil",
              variant: .primary,
              size: .lg,
              fullWidth: true
            ) {
              logTarget = PlayerProgramLogTarget(
                assignmentId: program.assignment.id,
                date: scheduledDate
              )
            }
          }
        }
      }
      .navigationTitle("Programs")
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button { Task { await reload() } } label: { Image(systemName: "arrow.clockwise") }
        }
      }
      .onChange(of: selectedProgramId) { _, _ in
        Task { await loadSelectedProgramDays(resetSelection: true) }
      }
      .onChange(of: selectedWeek) { _, _ in repairDaySelection() }
      .sheet(item: $logTarget) { target in
        NavigationStack {
          SDPlayerTodayViewInternal(
            initialDate: target.date,
            preferredAssignmentId: target.assignmentId
          )
          .environmentObject(appState)
          .toolbar {
            ToolbarItem(placement: .cancellationAction) {
              Button("Close") { logTarget = nil }
            }
          }
        }
      }
      .alert("Programs", isPresented: Binding(get: { errorText != nil }, set: { _ in errorText = nil })) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(errorText ?? "")
      }
      .task(id: appState.activeOrgAuthorizationKey) { await reload() }
    }
  }

  private func reload() async {
    guard let supabase = appState.supabase else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      let session = try await supabase.client.auth.session
      let assignments = try await supabase.fetchProgramAssignments(
        playerId: session.user.id,
        orgId: appState.activeOrgId
      )
      let loadedTemplates = try await supabase.fetchProgramTemplates(ids: assignments.map(\.template_id))
      let templatesById = Dictionary(uniqueKeysWithValues: loadedTemplates.map { ($0.id, $0) })
      let resolved = assignments.compactMap { assignment -> PlayerProgramRecord? in
        guard let template = templatesById[assignment.template_id] else { return nil }
        return PlayerProgramRecord(assignment: assignment, template: template)
      }
      programs = resolved.sorted { lhs, rhs in
        if lhs.isActive != rhs.isActive { return lhs.isActive }
        return lhs.assignment.start_date > rhs.assignment.start_date
      }
      if selectedProgramId == nil || !programs.contains(where: { $0.id == selectedProgramId }) {
        selectedProgramId = programs.first?.id
      }
      if resolved.count != assignments.count {
        errorText = "Some older program records reference a template that is no longer available. Every valid program is still shown."
      }
      await loadSelectedProgramDays(resetSelection: false)
    } catch {
      let message = SDApplicationErrorClassifier.alertMessage(for: error) ?? "Please try again."
      errorText = "Programs could not be refreshed. Previously loaded programs remain visible. \(message)"
    }
  }

  private func loadSelectedProgramDays(resetSelection: Bool) async {
    guard let supabase = appState.supabase, let program = selectedProgram else {
      days = []
      return
    }
    do {
      let loadedDays = try await supabase.fetchProgramDays(templateId: program.template.id)
      guard selectedProgram?.id == program.id else { return }
      days = loadedDays
      if resetSelection {
        selectedWeek = availableWeeks.first ?? 1
        selectedDay = availableDays.first ?? 1
      } else {
        selectedWeek = availableWeeks.contains(selectedWeek) ? selectedWeek : (availableWeeks.first ?? 1)
        repairDaySelection()
      }
    } catch {
      let message = SDApplicationErrorClassifier.alertMessage(for: error) ?? "Please try again."
      errorText = "This program's days could not be refreshed. Previously loaded details remain visible. \(message)"
    }
  }

  private func repairDaySelection() {
    if !availableDays.contains(selectedDay) {
      selectedDay = availableDays.first ?? 1
    }
  }

  private func line(_ exercise: SDExercise) -> String {
    let sets = exercise.sets.map(String.init) ?? "—"
    let reps = (exercise.reps ?? "—").isEmpty ? "—" : (exercise.reps ?? "—")
    let unit = (exercise.unit ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    return unit.isEmpty ? "\(sets) x \(reps)" : "\(sets) x \(reps) • \(unit)"
  }
}

private struct PlayerProgramRecord: Identifiable {
  let assignment: SDProgramAssignment
  let template: SDProgramTemplate
  var id: UUID { assignment.id }
  var isActive: Bool { assignment.ended_at == nil }
  var pickerLabel: String { "\(isActive ? "Active" : "Ended") • \(template.name)" }
  var detailLine: String {
    let endText = assignment.ended_at.map { " • Ended \($0.formatted(date: .abbreviated, time: .omitted))" } ?? ""
    return "\(template.kind.title) • Starts \(assignment.start_date) • \(template.weeks) weeks\(endText)"
  }
}

private struct PlayerProgramLogTarget: Identifiable {
  let assignmentId: UUID
  let date: Date
  var id: String { "\(assignmentId.uuidString):\(DateUtils.toISODate(date))" }
}
