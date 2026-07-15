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
      List {
        if isLoading {
          HStack(spacing: 10) { ProgressView(); Text("Loading…").foregroundStyle(.secondary) }
        }

        Section("Active programs") {
          if activePrograms.isEmpty {
            ContentUnavailableView(
              "No active programs",
              systemImage: "figure.strengthtraining.traditional",
              description: Text("Your coach can assign S&C, hitting, and pitching programs independently.")
            )
          } else {
            Picker("Program", selection: $selectedProgramId) {
              ForEach(activePrograms) { program in
                Label(program.label, systemImage: program.template.kind.systemImage)
                  .tag(Optional(program.id))
              }
            }
            .pickerStyle(.menu)

            if let program = selectedProgram {
              Text(program.template.name).font(.headline)
              Text("\(program.template.kind.title) • Starts \(program.assignment.start_date) • \(program.template.weeks) weeks")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
        }

        if let template = selectedProgram?.template {
          Section("Browse \(template.kind.title) plan") {
            Picker("Week", selection: $selectedWeek) {
              ForEach(1...template.weeks, id: \.self) { Text("Week \($0)").tag($0) }
            }
            Picker("Day", selection: $selectedDay) {
              ForEach(1...max(1, template.lift_weekdays.count), id: \.self) { Text("Day \($0)").tag($0) }
            }
          }

          Section(template.kind == .strength ? "Exercises" : "Drills") {
            let exercises = days.first(where: { $0.week == selectedWeek && $0.day_index == selectedDay })?.exercises ?? []
            if exercises.isEmpty {
              Text("No items are set for this day yet.")
                .foregroundStyle(.secondary)
            } else {
              ForEach(exercises, id: \.id) { exercise in
                VStack(alignment: .leading, spacing: 3) {
                  Text(exercise.name).font(.headline)
                  Text(line(exercise)).font(.caption).foregroundStyle(.secondary)
                  if let notes = exercise.notes, !notes.isEmpty {
                    Text(notes).font(.caption).foregroundStyle(.secondary)
                  }
                }
                .padding(.vertical, 4)
              }
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
