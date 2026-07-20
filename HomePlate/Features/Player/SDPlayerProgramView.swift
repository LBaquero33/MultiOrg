import SwiftUI

struct SDPlayerProgramView: View {
  @EnvironmentObject private var appState: AppState

  @State private var activePrograms: [PlayerActiveProgram] = []
  @State private var selectedProgramId: UUID?
  @State private var days: [SDProgramDay] = []
  @State private var selectedWeek = 1
  @State private var selectedDay = 1
  @State private var isLoading = false
  @State private var errorText: String?

  private var selectedProgram: PlayerActiveProgram? {
    guard let selectedProgramId else { return nil }
    return activePrograms.first { $0.id == selectedProgramId }
  }

  var body: some View {
    NavigationStack {
      HPDetailScreenLayout {
        HPWorkspaceHeader(
          "Programs",
          context: selectedProgram.map { "\($0.template.kind.title) • \($0.template.name)" }
            ?? "Your active development plans"
        )
      } metrics: {
        EmptyView()
      } details: {
        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            HPSectionHeader("Active programs")

            if isLoading {
              HPLoadingState(text: "Loading programs…")
            }

            if activePrograms.isEmpty {
              HPEmptyState(
                title: "No active programs",
                message: "Your coach can assign S&C, hitting, and pitching programs independently.",
                systemImage: "figure.strengthtraining.traditional"
              )
            } else {
              Picker("Program", selection: $selectedProgramId) {
                ForEach(activePrograms) { program in
                  Label(program.label, systemImage: program.template.kind.systemImage)
                    .tag(Optional(program.id))
                }
              }
              .pickerStyle(.menu)
              .tint(HP.Color.accent)

              if let program = selectedProgram {
                Text(program.template.name)
                  .font(HP.Font.headline)
                  .foregroundStyle(HP.Color.text)
                Text("\(program.template.kind.title) • Starts \(program.assignment.start_date) • \(program.template.weeks) weeks")
                  .font(HP.Font.caption)
                  .foregroundStyle(HP.Color.textMuted)
                  .fixedSize(horizontal: false, vertical: true)

                Divider().overlay(HP.Color.border)

                HPSectionHeader("Browse \(program.template.kind.title) plan")
                Picker("Week", selection: $selectedWeek) {
                  ForEach(1...program.template.weeks, id: \.self) { Text("Week \($0)").tag($0) }
                }
                .pickerStyle(.menu)
                .tint(HP.Color.accent)
                Picker("Day", selection: $selectedDay) {
                  ForEach(1...max(1, program.template.lift_weekdays.count), id: \.self) {
                    Text("Day \($0)").tag($0)
                  }
                }
                .pickerStyle(.menu)
                .tint(HP.Color.accent)
              }
            }
          }
        }
      } related: { _ in
        if let template = selectedProgram?.template {
          HPCard {
            VStack(alignment: .leading, spacing: HP.Space.sm) {
              HPSectionHeader(template.kind == .strength ? "Exercises" : "Drills")
              let exercises = days.first(where: {
                $0.week == selectedWeek && $0.day_index == selectedDay
              })?.exercises ?? []
              if exercises.isEmpty {
                HPEmptyState(
                  title: "No items yet",
                  message: "No items are set for this day yet.",
                  systemImage: template.kind.systemImage
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
        EmptyView()
      }
      .navigationTitle("Programs")
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button { Task { await reload() } } label: { Image(systemName: "arrow.clockwise") }
        }
      }
      .onChange(of: selectedProgramId) { _, _ in
        Task { await loadSelectedProgramDays() }
      }
      .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { _ in errorText = nil })) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(errorText ?? "")
      }
      .task { await reload() }
    }
  }

  private func reload() async {
    guard let supabase = appState.supabase else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      let session = try await supabase.client.auth.session
      let assignments = try await supabase.fetchActiveAssignments(playerId: session.user.id)
      var resolved: [PlayerActiveProgram] = []
      for assignment in assignments {
        let template = try await supabase.fetchTemplate(id: assignment.template_id)
        resolved.append(PlayerActiveProgram(assignment: assignment, template: template))
      }
      activePrograms = resolved.sorted { lhs, rhs in
        lhs.template.kind.rawValue < rhs.template.kind.rawValue
      }
      if selectedProgramId == nil || !activePrograms.contains(where: { $0.id == selectedProgramId }) {
        selectedProgramId = activePrograms.first?.id
      }
      await loadSelectedProgramDays()
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func loadSelectedProgramDays() async {
    guard let supabase = appState.supabase, let program = selectedProgram else {
      days = []
      return
    }
    do {
      days = try await supabase.fetchProgramDays(templateId: program.template.id)
      selectedWeek = min(max(1, selectedWeek), program.template.weeks)
      selectedDay = min(max(1, selectedDay), max(1, program.template.lift_weekdays.count))
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func line(_ exercise: SDExercise) -> String {
    let sets = exercise.sets.map(String.init) ?? "—"
    let reps = (exercise.reps ?? "—").isEmpty ? "—" : (exercise.reps ?? "—")
    let unit = (exercise.unit ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    return unit.isEmpty ? "\(sets) x \(reps)" : "\(sets) x \(reps) • \(unit)"
  }
}

private struct PlayerActiveProgram: Identifiable {
  let assignment: SDProgramAssignment
  let template: SDProgramTemplate
  var id: UUID { assignment.id }
  var label: String { "\(template.kind.title): \(template.name)" }
}
