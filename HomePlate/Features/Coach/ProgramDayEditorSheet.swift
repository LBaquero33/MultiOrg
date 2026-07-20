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

  private var unitOptions: [String] { template.kind.unitOptions }

  var body: some View {
    NavigationStack {
      HPFormScreenLayout { _ in
        HPWorkspaceHeader(
          "Edit day",
          context: "Week \(week) • Day \(dayIndex) • \(template.kind.title)"
        )
      } sections: { context in
        dayStatusCard
        exercisesCard(context)
      } primaryAction: { context in
        HPButton(
          title: "Save",
          systemImage: "checkmark",
          variant: .primary,
          size: .lg,
          isLoading: isSaving,
          fullWidth: context.isAccessibilitySize,
          action: { Task { await save() } }
        )
        .disabled(!canSave || isSaving)
      } secondaryAction: { context in
        HPButton(
          title: "Cancel",
          variant: .secondary,
          size: .lg,
          fullWidth: context.isAccessibilitySize,
          action: { dismiss() }
        )
      }
      .navigationTitle("Edit day")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
            #if os(macOS)
            .keyboardShortcut(.cancelAction)
            #endif
        }
      }
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

  private var dayStatusCard: some View {
    HPCard {
      HPSectionHeader("Week \(week) • Day \(dayIndex)") {
        if isLoadingLibrary {
          HPProgressIndicator(style: .spinner)
            .accessibilityLabel("Loading exercise suggestions")
        }
      }
    }
  }

  private func exercisesCard(_ context: HPScreenLayoutContext) -> some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.md) {
        HPSectionHeader(template.kind == .strength ? "Exercises (in order)" : "Drills (in order)") {
          HPStatusBadge(text: "\(items.count)", kind: .neutral)
        }

        if items.isEmpty {
          Text("No exercises yet. Click Add.")
            .font(HP.Font.callout)
            .foregroundStyle(HP.Color.textMuted)
            .fixedSize(horizontal: false, vertical: true)
        }

        ForEach($items) { $ex in
          let exId = ex.id
          ExerciseRow(
            ex: $ex,
            suggestions: suggestions(for: ex.name),
            unitOptions: unitOptions,
            isStacked: !context.isExpanded,
            onDuplicate: { duplicate(exId) },
            onDelete: { delete(exId) },
            onMoveUp: { moveUp(exId) },
            onMoveDown: { moveDown(exId) }
          )
          .padding(HP.Space.sm)
          .background(
            RoundedRectangle(cornerRadius: HP.Radius.md, style: .continuous)
              .fill(HP.Color.surface)
          )
          .overlay(
            RoundedRectangle(cornerRadius: HP.Radius.md, style: .continuous)
              .strokeBorder(HP.Color.border, lineWidth: 1)
              .allowsHitTesting(false)
          )
        }

        HPButton(
          title: "Add exercise",
          systemImage: "plus",
          variant: .secondary,
          size: .md,
          fullWidth: !context.isExpanded,
          action: { items.append(EditableExercise()) }
        )
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
  let isStacked: Bool
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

    let nameLayout = isStacked
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: HP.Space.sm))
      : AnyLayout(HStackLayout(alignment: .top, spacing: HP.Space.sm))
    let fieldLayout = AnyLayout(
      VStackLayout(alignment: .leading, spacing: HP.Space.md)
    )

    VStack(alignment: .leading, spacing: HP.Space.md) {
      nameLayout {
        ExerciseNameAutocompleteField(text: $ex.name, suggestions: suggestions)
        if !isStacked {
          Spacer(minLength: HP.Space.sm)
        }
        Menu {
          Button("Move up", action: onMoveUp)
          Button("Move down", action: onMoveDown)
          Divider()
          Button("Duplicate", action: onDuplicate)
          Button("Delete", role: .destructive, action: onDelete)
        } label: {
          Image(systemName: "ellipsis.circle")
            .font(HP.Font.headline)
            .foregroundStyle(HP.Color.textTertiary)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Exercise actions")
      }

      fieldLayout {
        VStack(alignment: .leading, spacing: 6) {
          fieldLabel("Sets")
          HStack(spacing: HP.Space.xs) {
            TextField("—", text: setsText)
              .textFieldStyle(.plain)
              .font(HP.Font.body)
              .foregroundStyle(HP.Color.text)
              .multilineTextAlignment(.center)
              .padding(.horizontal, HP.Space.xs)
              .frame(minWidth: 54, maxWidth: 54, minHeight: 44)
              .background(
                RoundedRectangle(cornerRadius: HP.Radius.md, style: .continuous)
                  .fill(HP.Color.input)
              )
              .overlay(
                RoundedRectangle(cornerRadius: HP.Radius.md, style: .continuous)
                  .strokeBorder(HP.Color.border, lineWidth: 1)
                  .allowsHitTesting(false)
              )
            Stepper("", value: setsStepper, in: 0...20)
              .labelsHidden()
              .accessibilityLabel("Sets")
              .frame(minHeight: 44)
              .contentShape(Rectangle())
          }
        }
        .frame(maxWidth: isStacked ? .infinity : 210, alignment: .leading)

        HPFormField(label: "Reps", text: $ex.reps, placeholder: "Reps")
          .frame(maxWidth: isStacked ? .infinity : 160)

        VStack(alignment: .leading, spacing: 6) {
          fieldLabel("Unit")
          Picker("Unit", selection: $ex.unitChoice) {
            ForEach(unitOptions, id: \.self) { u in
              Text(u).tag(u)
            }
          }
          .labelsHidden()
          .accessibilityLabel("Unit")
          .pickerStyle(.menu)
          .tint(HP.Color.accent)
          .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
          .padding(.horizontal, HP.Space.xs)
          .background(
            RoundedRectangle(cornerRadius: HP.Radius.md, style: .continuous)
              .fill(HP.Color.input)
          )
          .overlay(
            RoundedRectangle(cornerRadius: HP.Radius.md, style: .continuous)
              .strokeBorder(HP.Color.border, lineWidth: 1)
              .allowsHitTesting(false)
          )
        }
        .frame(maxWidth: isStacked ? .infinity : 160)

        if ex.unitChoice == "other" {
          HPFormField(label: "Custom unit", text: $ex.customUnit, placeholder: "Custom")
            .frame(maxWidth: isStacked ? .infinity : 180)
        }
      }

      HPFormField(
        label: "Notes",
        text: $ex.notes,
        kind: .multiline,
        placeholder: "Optional coaching cues, tempo, setup, or intent"
      )
    }
  }

  private func fieldLabel(_ text: String) -> some View {
    Text(text.uppercased())
      .font(HP.Font.eyebrow)
      .tracking(HP.Font.eyebrowTracking)
      .foregroundStyle(HP.Color.textMuted)
      .fixedSize(horizontal: false, vertical: true)
  }
}

struct ExerciseNameAutocompleteField: View {
  @Binding var text: String
  let suggestions: [String]

  @FocusState private var focused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("EXERCISE NAME")
        .font(HP.Font.eyebrow)
        .tracking(HP.Font.eyebrowTracking)
        .foregroundStyle(HP.Color.textMuted)
        .fixedSize(horizontal: false, vertical: true)

      TextField("Exercise name", text: $text)
        .textFieldStyle(.plain)
        .font(HP.Font.body)
        .foregroundStyle(HP.Color.text)
        .focused($focused)
        .accessibilityLabel("Exercise name")
        .padding(.horizontal, HP.Space.sm)
        .padding(.vertical, 10)
        .background(
          RoundedRectangle(cornerRadius: HP.Radius.md, style: .continuous)
            .fill(HP.Color.input)
        )
        .overlay(
          RoundedRectangle(cornerRadius: HP.Radius.md, style: .continuous)
            .strokeBorder(focused ? HP.Color.focusRing : HP.Color.border, lineWidth: focused ? 2 : 1)
            .allowsHitTesting(false)
        )

      if focused, !suggestions.isEmpty {
        VStack(alignment: .leading, spacing: 2) {
          ForEach(suggestions.prefix(6), id: \.self) { s in
            Button {
              text = s
              focused = false
            } label: {
              Text(s)
                .font(HP.Font.callout)
                .foregroundStyle(HP.Color.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 44)
                .padding(.horizontal, HP.Space.sm)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(HP.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: HP.Radius.sm, style: .continuous))
          }
        }
        .padding(HP.Space.xs)
        .background(HP.Color.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: HP.Radius.md, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: HP.Radius.md, style: .continuous)
            .strokeBorder(HP.Color.border, lineWidth: 1)
            .allowsHitTesting(false)
        )
      }
    }
  }
}
