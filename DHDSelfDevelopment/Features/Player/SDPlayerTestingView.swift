import SwiftUI

struct SDPlayerTestingView: View {
  @EnvironmentObject private var appState: AppState

  @State private var entries: [SDTestingEntry] = []
  @State private var isLoading = false
  @State private var showAdd = false
  @State private var errorText: String?

  var body: some View {
    NavigationStack {
      List {
        if isLoading {
          HStack(spacing: 10) { ProgressView(); Text("Loading…").foregroundStyle(.secondary) }
        }
        if entries.isEmpty, !isLoading {
          Text("No testing entries yet.")
            .foregroundStyle(.secondary)
        } else {
          Section("Entries") {
            ForEach(entries) { e in
              VStack(alignment: .leading, spacing: 4) {
                Text(e.entry_date).font(.headline)
                Text(summary(e)).font(.caption).foregroundStyle(.secondary)
              }
              .padding(.vertical, 4)
            }
          }
        }
      }
      .navigationTitle("Testing")
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button { showAdd = true } label: { Image(systemName: "plus") }
        }
        ToolbarItem(placement: .secondaryAction) {
          Menu {
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
      .sheet(isPresented: $showAdd) {
        AddTestingEntrySheet { newEntry in
          entries.insert(newEntry, at: 0)
        }
        .environmentObject(appState)
      }
      .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { _ in errorText = nil })) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(errorText ?? "")
      }
      .task {
        await reload()
      }
    }
  }

  private func reload() async {
    guard let supabase = appState.supabase else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      let session = try await supabase.client.auth.session
      let uid = session.user.id
      entries = try await supabase.listTestingEntries(playerId: uid)
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func summary(_ e: SDTestingEntry) -> String {
    var parts: [String] = []
    if let v = e.squat_1rm { parts.append("Squat \(fmt(v))") }
    if let v = e.bench_1rm { parts.append("Bench \(fmt(v))") }
    if let v = e.deadlift_1rm { parts.append("Deadlift \(fmt(v))") }
    if let v = e.max_exit_velo { parts.append("MaxEV \(fmt(v))") }
    if let v = e.avg_exit_velo { parts.append("AvgEV \(fmt(v))") }
    if parts.isEmpty { return "—" }
    return parts.joined(separator: " • ")
  }

  private func fmt(_ v: Double) -> String {
    if v.rounded() == v { return String(Int(v)) }
    return String(format: "%.1f", v)
  }
}

private struct AddTestingEntrySheet: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var appState: AppState
  let onSaved: (SDTestingEntry) -> Void

  @State private var date = Date()
  @State private var heightIn = ""
  @State private var weightLb = ""
  @State private var squat = ""
  @State private var bench = ""
  @State private var deadlift = ""
  @State private var maxEV = ""
  @State private var avgEV = ""
  @State private var hipER = ""
  @State private var hipIR = ""
  @State private var shoulderIR = ""
  @State private var shoulderER = ""
  @State private var notes = ""
  @State private var isSaving = false
  @State private var errorText: String?

  private struct NumericKeyboard: ViewModifier {
    func body(content: Content) -> some View {
      #if canImport(UIKit)
      return content.keyboardType(.decimalPad)
      #else
      return content
      #endif
    }
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Date") {
          DatePicker("Entry date", selection: $date, displayedComponents: .date)
        }
        Section("Body") {
          TextField("Height (in)", text: $heightIn).modifier(NumericKeyboard())
          TextField("Weight (lb)", text: $weightLb).modifier(NumericKeyboard())
        }
        Section("Strength") {
          TextField("Squat 1RM", text: $squat).modifier(NumericKeyboard())
          TextField("Bench 1RM", text: $bench).modifier(NumericKeyboard())
          TextField("Deadlift 1RM", text: $deadlift).modifier(NumericKeyboard())
        }
        Section("Hitting") {
          TextField("Max EV (mph)", text: $maxEV).modifier(NumericKeyboard())
          TextField("Avg EV (mph)", text: $avgEV).modifier(NumericKeyboard())
        }
        Section("Mobility diffs") {
          TextField("Hip ER difference", text: $hipER).modifier(NumericKeyboard())
          TextField("Hip IR difference", text: $hipIR).modifier(NumericKeyboard())
          TextField("Shoulder IR difference", text: $shoulderIR).modifier(NumericKeyboard())
          TextField("Shoulder ER difference", text: $shoulderER).modifier(NumericKeyboard())
        }
        Section("Notes") {
          TextField("Notes (optional)", text: $notes, axis: .vertical)
        }
      }
      .navigationTitle("Add entry")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button {
            Task { await save() }
          } label: {
            if isSaving { ProgressView() } else { Text("Save") }
          }
          .disabled(isSaving)
        }
      }
      .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { _ in errorText = nil })) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(errorText ?? "")
      }
    }
  }

  private func toDouble(_ s: String) -> Double? {
    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    if t.isEmpty { return nil }
    return Double(t)
  }

  private func save() async {
    guard let supabase = appState.supabase else { return }
    isSaving = true
    defer { isSaving = false }
    do {
      let session = try await supabase.client.auth.session
      let uid = session.user.id
      let create = SDTestingEntryCreate(
        org_id: appState.activeOrgId,
        player_id: uid,
        entry_date: DateUtils.toISODate(date),
        height_in: toDouble(heightIn),
        weight_lb: toDouble(weightLb),
        squat_1rm: toDouble(squat),
        bench_1rm: toDouble(bench),
        deadlift_1rm: toDouble(deadlift),
        max_exit_velo: toDouble(maxEV),
        avg_exit_velo: toDouble(avgEV),
        hip_er_diff: toDouble(hipER),
        hip_ir_diff: toDouble(hipIR),
        shoulder_ir_diff: toDouble(shoulderIR),
        shoulder_er_diff: toDouble(shoulderER),
        notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes
      )
      let saved = try await supabase.upsertTestingEntry(create)
      onSaved(saved)
      dismiss()
    } catch {
      errorText = error.localizedDescription
    }
  }
}
