import SwiftUI

struct ProgramDayEditorSheet: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var appState: AppState

  let template: SDProgramTemplate
  let week: Int
  let dayIndex: Int
  let existing: SDProgramDay?
  let onSaved: (SDProgramDay) -> Void

  @State private var items: [EditableExercise] = []
  @State private var library: [SDExerciseLibraryItem] = []
  @State private var isLoadingLibrary = false
  @State private var isSaving = false
  @State private var errorText: String?

  private let unitOptions: [String] = ["lb", "kg", "sec", "min", "in", "ft", "m", "yd", "bw", "band", "other"]

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        List {
          Section {
            HStack {
              Text("Week \(week) • Day \(dayIndex)")
                .font(.headline)
              Spacer()
              if isLoadingLibrary {
                ProgressView().controlSize(.small)
              }
            }
          }

          Section("Exercises (in order)") {
            if items.isEmpty {
              Text("No exercises yet. Click Add.")
                .foregroundStyle(.secondary)
            }

            ForEach($items) { $ex in
              let exId = ex.id
              ExerciseRow(
                ex: $ex,
                suggestions: suggestions(for: ex.name),
                unitOptions: unitOptions,
                onDuplicate: { duplicate(exId) },
                onDelete: { delete(exId) },
                onMoveUp: { moveUp(exId) },
                onMoveDown: { moveDown(exId) }
              )
              .padding(.vertical, 4)
            }

            Button {
              items.append(EditableExercise())
            } label: {
              Label("Add exercise", systemImage: "plus")
            }
          }
        }

        // Bottom bar (fast actions, clean)
        HStack(spacing: 10) {
          // Cross-platform reordering uses per-row menu actions (Move up/down).
          Spacer()
          Button("Cancel") { dismiss() }
            .buttonStyle(.bordered)
          Button {
            Task { await save() }
          } label: {
            if isSaving { ProgressView() } else { Text("Save").fontWeight(.semibold) }
          }
          .buttonStyle(.borderedProminent)
          .disabled(!canSave || isSaving)
        }
        .padding()
        .background(.thinMaterial)
      }
      .navigationTitle("Edit day")
      #if os(macOS)
      .frame(minWidth: 820, minHeight: 620)
      #endif
      .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { _ in errorText = nil })) {
        Button("OK", role: .cancel) {}
      } message: { Text(errorText ?? "") }
      .task {
        preload()
        await loadLibraryIfNeeded()
      }
    }
  }

  private var canSave: Bool {
    // Save disabled until all visible exercise names are non-empty.
    // Allow saving with zero exercises.
    for ex in items {
      if ex.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
    }
    return true
  }

  private func preload() {
    guard items.isEmpty else { return }
    let existingEx = existing?.exercises ?? []
    items = existingEx.map { EditableExercise(from: $0) }
  }

  private func loadLibraryIfNeeded() async {
    guard let supabase = appState.supabase else { return }
    isLoadingLibrary = true
    defer { isLoadingLibrary = false }
    do {
      library = try await supabase.listExerciseLibrary(forceRefresh: false)
    } catch {
      // Non-fatal: editor still works without suggestions.
      library = []
    }
  }

  private func suggestions(for raw: String) -> [String] {
    let q = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !q.isEmpty else { return Array(library.prefix(12)).map(\.name) }

    let prefix = library.filter { $0.name_norm.hasPrefix(q) }
    let contains = library.filter { !$0.name_norm.hasPrefix(q) && $0.name_norm.contains(q) }
    return Array((prefix + contains).prefix(8)).map(\.name)
  }

  private func move(from: IndexSet, to: Int) {
    items.move(fromOffsets: from, toOffset: to)
  }

  private func moveUp(_ id: UUID) {
    guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
    guard idx > 0 else { return }
    items.swapAt(idx, idx - 1)
  }

  private func moveDown(_ id: UUID) {
    guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
    guard idx < items.count - 1 else { return }
    items.swapAt(idx, idx + 1)
  }

  private func delete(_ id: UUID) {
    items.removeAll(where: { $0.id == id })
  }

  private func duplicate(_ id: UUID) {
    guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
    var copy = items[idx]
    copy.id = UUID()
    items.insert(copy, at: idx + 1)
  }

  private func save() async {
    guard let supabase = appState.supabase else { return }
    isSaving = true
    defer { isSaving = false }
    do {
      let exercises = items
        .map { $0.toSDExercise() }
        .map { ex in
          var clean = ex
          clean.name = clean.name.trimmingCharacters(in: .whitespacesAndNewlines)
          clean.reps = (clean.reps ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
          clean.unit = (clean.unit ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
          clean.notes = (clean.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
          if clean.reps?.isEmpty == true { clean.reps = nil }
          if clean.unit?.isEmpty == true { clean.unit = nil }
          if clean.notes?.isEmpty == true { clean.notes = nil }
          return clean
        }
        .filter { !$0.name.isEmpty }

      let saved = try await supabase.upsertProgramDay(
        templateId: template.id,
        week: week,
        dayIndex: dayIndex,
        exercises: exercises
      )

      // Update autocomplete library (best-effort).
      let names = exercises.map(\.name)
      try? await supabase.upsertExerciseLibrary(names: names)

      onSaved(saved)
      dismiss()
    } catch {
      errorText = error.localizedDescription
    }
  }
}

struct EditableExercise: Identifiable, Hashable {
  var id: UUID = UUID()
  var name: String = ""
  var sets: Int? = nil
  var reps: String = ""
  var unitChoice: String = "lb"
  var customUnit: String = ""
  var notes: String = ""
  var showNotes: Bool = false

  init() {}

  init(from ex: SDExercise) {
    id = ex.id
    name = ex.name
    sets = ex.sets
    reps = ex.reps ?? ""
    notes = ex.notes ?? ""
    let u = (ex.unit ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if u.isEmpty {
      unitChoice = "lb"
      customUnit = ""
    } else if ["lb", "kg", "sec", "min", "in", "ft", "m", "yd", "bw", "band"].contains(u) {
      unitChoice = u
      customUnit = ""
    } else {
      unitChoice = "other"
      customUnit = u
    }
    showNotes = !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  func toSDExercise() -> SDExercise {
    let unit: String?
    if unitChoice == "other" {
      let cu = customUnit.trimmingCharacters(in: .whitespacesAndNewlines)
      unit = cu.isEmpty ? nil : cu
    } else {
      unit = unitChoice
    }
    let r = reps.trimmingCharacters(in: .whitespacesAndNewlines)
    let n = notes.trimmingCharacters(in: .whitespacesAndNewlines)
    return SDExercise(
      id: id,
      name: name,
      sets: sets,
      reps: r.isEmpty ? nil : r,
      unit: unit,
      notes: n.isEmpty ? nil : n
    )
  }
}

private struct ExerciseRow: View {
  @Binding var ex: EditableExercise
  let suggestions: [String]
  let unitOptions: [String]
  let onDuplicate: () -> Void
  let onDelete: () -> Void
  let onMoveUp: () -> Void
  let onMoveDown: () -> Void

  var body: some View {
    let setsText = Binding<String>(
      get: { ex.sets.map(String.init) ?? "" },
      set: { raw in
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty {
          ex.sets = nil
          return
        }
        if let v = Int(t) {
          ex.sets = v <= 0 ? nil : min(20, v)
        }
      }
    )

    let setsStepper = Binding<Int>(
      get: { ex.sets ?? 0 },
      set: { newValue in ex.sets = newValue <= 0 ? nil : newValue }
    )

    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .top, spacing: 10) {
        ExerciseNameAutocompleteField(text: $ex.name, suggestions: suggestions)
        Spacer()
        Menu {
          Button("Move up", action: onMoveUp)
          Button("Move down", action: onMoveDown)
          Divider()
          Button("Duplicate", action: onDuplicate)
          Button("Delete", role: .destructive, action: onDelete)
        } label: {
          Image(systemName: "ellipsis.circle")
            .font(.headline)
            .foregroundStyle(.secondary)
        }
      }

      HStack(spacing: 10) {
        HStack(spacing: 8) {
          Text("Sets")
            .foregroundStyle(DHDTheme.textSecondary)
          TextField("—", text: setsText)
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .frame(width: 54)
            .multilineTextAlignment(.center)
          Stepper("", value: setsStepper, in: 0...20)
            .labelsHidden()
        }
        .frame(maxWidth: 210, alignment: .leading)

        TextField("Reps", text: $ex.reps)
          .textFieldStyle(RoundedBorderTextFieldStyle())
          .frame(maxWidth: 160)

        Picker("Unit", selection: $ex.unitChoice) {
          ForEach(unitOptions, id: \.self) { u in
            Text(u).tag(u)
          }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: 160)

        if ex.unitChoice == "other" {
          TextField("Custom", text: $ex.customUnit)
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .frame(maxWidth: 180)
        }
      }

      VStack(alignment: .leading, spacing: 6) {
        Text("Notes")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(DHDTheme.textSecondary)
        TextEditor(text: $ex.notes)
          .frame(minHeight: 64)
          .padding(8)
          .background(Color.black.opacity(0.04))
          .clipShape(RoundedRectangle(cornerRadius: 10))
          .overlay(
            RoundedRectangle(cornerRadius: 10)
              .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
          )
          .overlay(alignment: .topLeading) {
            if ex.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
              Text("Optional coaching cues, tempo, setup, or intent")
                .foregroundStyle(DHDTheme.textSecondary.opacity(0.7))
                .padding(.horizontal, 14)
                .padding(.vertical, 16)
                .allowsHitTesting(false)
            }
          }
      }
    }
  }
}

struct ExerciseNameAutocompleteField: View {
  @Binding var text: String
  let suggestions: [String]

  @FocusState private var focused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      TextField("Exercise name", text: $text)
        .textFieldStyle(RoundedBorderTextFieldStyle())
        .focused($focused)

      if focused, !suggestions.isEmpty {
        VStack(alignment: .leading, spacing: 2) {
          ForEach(suggestions.prefix(6), id: \.self) { s in
            Button {
              text = s
              focused = false
            } label: {
              Text(s)
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
            }
            .buttonStyle(.plain)
            .background(Color.black.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 10))
          }
        }
        .padding(8)
        .background(DHDTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
          RoundedRectangle(cornerRadius: 12)
            .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
        )
      }
    }
  }
}
