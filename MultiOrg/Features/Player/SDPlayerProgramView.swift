import SwiftUI

struct SDPlayerProgramView: View {
  @EnvironmentObject private var appState: AppState

  @State private var assignment: SDProgramAssignment?
  @State private var template: SDProgramTemplate?
  @State private var days: [SDProgramDay] = []
  @State private var selectedWeek = 1
  @State private var selectedDay = 1
  @State private var isLoading = false
  @State private var errorText: String?

  var body: some View {
    NavigationStack {
      List {
        if isLoading {
          HStack(spacing: 10) { ProgressView(); Text("Loading…").foregroundStyle(.secondary) }
        }

        Section("Current program") {
          if let assignment, let template {
            Text(template.name).font(.headline)
            Text("Start: \(assignment.start_date) • \(template.weeks) weeks • \(template.lift_weekdays.count) lifts/week")
              .font(.caption)
              .foregroundStyle(.secondary)
          } else {
            Text("No active program assigned.")
              .foregroundStyle(.secondary)
          }
        }

        if let template, !days.isEmpty {
          Section("Browse") {
            Picker("Week", selection: $selectedWeek) {
              ForEach(1...template.weeks, id: \.self) { Text("Week \($0)").tag($0) }
            }
            Picker("Day", selection: $selectedDay) {
              ForEach(1...max(1, template.lift_weekdays.count), id: \.self) { Text("Day \($0)").tag($0) }
            }
          }

          Section("Exercises") {
            let ex = days.first(where: { $0.week == selectedWeek && $0.day_index == selectedDay })?.exercises ?? []
            if ex.isEmpty {
              Text("No exercises set for this day yet.")
                .foregroundStyle(.secondary)
            } else {
              ForEach(ex, id: \.name) { e in
                VStack(alignment: .leading, spacing: 2) {
                  Text(e.name).font(.headline)
                  Text(line(e)).font(.caption).foregroundStyle(.secondary)
                  if let n = e.notes, !n.isEmpty {
                    Text(n).font(.caption).foregroundStyle(.secondary)
                  }
                }
                .padding(.vertical, 4)
              }
            }
          }
        }
      }
      .navigationTitle("Program")
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button {
            Task { await reload() }
          } label: { Image(systemName: "arrow.clockwise") }
        }
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
      let uid = session.user.id
      assignment = try await supabase.fetchActiveAssignment(playerId: uid)
      if let assignment {
        template = try await supabase.fetchTemplate(id: assignment.template_id)
        if let template {
          days = try await supabase.fetchProgramDays(templateId: template.id)
          selectedWeek = min(max(1, selectedWeek), template.weeks)
          selectedDay = min(max(1, selectedDay), max(1, template.lift_weekdays.count))
        } else {
          days = []
        }
      } else {
        template = nil
        days = []
      }
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func line(_ e: SDExercise) -> String {
    let s = e.sets.map(String.init) ?? "—"
    let r = (e.reps ?? "—").isEmpty ? "—" : (e.reps ?? "—")
    let u = (e.unit ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    return u.isEmpty ? "\(s) x \(r)" : "\(s) x \(r) • \(u)"
  }
}
