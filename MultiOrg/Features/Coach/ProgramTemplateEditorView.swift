import SwiftUI

struct ProgramTemplateEditorView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var appState: AppState
  let template: SDProgramTemplate
  var onDuplicated: (SDProgramTemplate) -> Void = { _ in }
  var onDeleted: () -> Void = {}

  @State private var days: [SDProgramDay] = []
  @State private var isLoading = false
  @State private var errorText: String?
  @State private var toastText: String?

  @State private var editingCell: GridCellKey?
  @State private var showCopyMenu = false
  @State private var showClearMenu = false
  @State private var copyPrefill: ProgramCopyPrefill?
  @State private var clearPrefill: ProgramClearPrefill?
  @State private var isMutatingTemplate = false
  @State private var confirmDeleteTemplate = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        headerCard
        gridCard
      }
      .padding(DHDTheme.pagePadding)
      .frame(maxWidth: .infinity, alignment: .leading)
      .frame(maxHeight: .infinity, alignment: .topLeading)
    }
    .background(DHDTheme.pageBackground)
    .navigationTitle("Edit \(template.kind.title) program")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button { Task { await reload() } } label: { Image(systemName: "arrow.clockwise") }
          .help("Refresh")
      }
    }
    .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { _ in errorText = nil })) {
      Button("OK", role: .cancel) {}
    } message: { Text(errorText ?? "") }
    .confirmationDialog("Delete this program?", isPresented: $confirmDeleteTemplate, titleVisibility: .visible) {
      Button("Delete Program", role: .destructive) { Task { await deleteTemplate() } }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("This permanently removes the template and all of its workout days. Assigned programs must be ended first.")
    }
    .task { await reload() }
    .dhdToast($toastText)
    .sheet(item: $editingCell) { key in
      ProgramDayEditorSheet(
        template: template,
        week: key.week,
        dayIndex: key.dayIndex,
        existing: dayMap[dayKey(week: key.week, dayIndex: key.dayIndex)]
      ) { savedDay in
        // Update local cache
        days.removeAll(where: { $0.week == savedDay.week && $0.day_index == savedDay.day_index })
        days.append(savedDay)
        days.sort { ($0.week, $0.day_index) < ($1.week, $1.day_index) }
        toastText = "Saved"
      }
      .environmentObject(appState)
      .presentationDetents([.large])
    }
    .sheet(isPresented: $showCopyMenu) {
      ProgramCopySheet(template: template, prefill: copyPrefill, onApply: { op in
        Task { await applyCopyOperation(op) }
      })
      .environmentObject(appState)
      .presentationDetents([.large])
    }
    .sheet(isPresented: $showClearMenu) {
      ProgramClearSheet(template: template, prefill: clearPrefill, onApply: { op in
        Task { await applyClearOperation(op) }
      })
      .environmentObject(appState)
      .presentationDetents([.medium, .large])
    }
  }

  private var headerCard: some View {
    DHDHeaderCard {
      VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .firstTextBaseline) {
          VStack(alignment: .leading, spacing: 2) {
            Text(template.name)
              .font(.title3.weight(.semibold))
            Text("\(template.kind.title) • \(template.weeks) weeks • \(template.lift_weekdays.count) days/week • \(weekdayLabel(template.lift_weekdays))")
              .font(.caption)
              .foregroundStyle(Color.white.opacity(0.88))
          }
          Spacer()
        }

        HStack(spacing: 10) {
          Button {
            Task { await duplicateTemplate() }
          } label: {
            Label("Duplicate Program", systemImage: "plus.square.on.square")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.bordered)
          .tint(.white.opacity(0.9))
          .disabled(isMutatingTemplate)

          Button {
            copyPrefill = nil
            showCopyMenu = true
          } label: {
            Label("Copy…", systemImage: "doc.on.doc")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.bordered)
          .tint(.white.opacity(0.9))

          Button {
            clearPrefill = nil
            showClearMenu = true
          } label: {
            Label("Clear…", systemImage: "trash")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.bordered)
          .tint(.white.opacity(0.85))

          Button(role: .destructive) {
            confirmDeleteTemplate = true
          } label: {
            Label("Delete Program", systemImage: "trash")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.bordered)
          .tint(.red)
          .disabled(isMutatingTemplate)
        }
      }
      .foregroundStyle(.white)
    }
  }

  private var gridCard: some View {
    DHDCard {
      VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .firstTextBaseline) {
          Text("Program grid")
            .font(.headline)
          Spacer()
          if isLoading {
            HStack(spacing: 8) { ProgressView(); Text("Loading…").foregroundStyle(.secondary) }
          }
        }

        ProgramTemplateGridView(
          template: template,
          dayMap: dayMap,
          onSelectCell: { week, dayIndex in
            editingCell = GridCellKey(week: week, dayIndex: dayIndex)
          },
          onCopyCell: { week, dayIndex in
            copyPrefill = .day(srcWeek: week, srcDay: dayIndex)
            showCopyMenu = true
          },
          onClearCell: { week, dayIndex in
            clearPrefill = .day(week: week, day: dayIndex)
            showClearMenu = true
          }
        )
      }
    }
  }

  private var dayMap: [String: SDProgramDay] {
    var out: [String: SDProgramDay] = [:]
    for d in days {
      out[dayKey(week: d.week, dayIndex: d.day_index)] = d
    }
    return out
  }

  private func dayKey(week: Int, dayIndex: Int) -> String { "\(week)-\(dayIndex)" }

  private func weekdayLabel(_ days: [Int]) -> String {
    let map: [Int: String] = [1: "Mon", 2: "Tue", 3: "Wed", 4: "Thu", 5: "Fri", 6: "Sat", 7: "Sun"]
    return days.compactMap { map[$0] }.joined(separator: ", ")
  }

  private func reload() async {
    guard let supabase = appState.supabase else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      days = try await supabase.fetchProgramDays(templateId: template.id)
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func applyCopyOperation(_ op: ProgramCopyOperation) async {
    guard let supabase = appState.supabase else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      switch op {
      case .copyDay(let src, let dst):
        let exercises = independentCopy(dayMap[dayKey(week: src.week, dayIndex: src.dayIndex)]?.exercises ?? [])
        let saved = try await supabase.upsertProgramDay(templateId: template.id, week: dst.week, dayIndex: dst.dayIndex, exercises: exercises)
        days.removeAll(where: { $0.week == dst.week && $0.day_index == dst.dayIndex })
        days.append(saved)

      case .copyWeek(let srcWeek, let dstWeek):
        try await withThrowingTaskGroup(of: SDProgramDay.self) { group in
          for d in 1...template.lift_weekdays.count {
            let exercises = independentCopy(dayMap[dayKey(week: srcWeek, dayIndex: d)]?.exercises ?? [])
            group.addTask {
              try await supabase.upsertProgramDay(templateId: template.id, week: dstWeek, dayIndex: d, exercises: exercises)
            }
          }
          var saved: [SDProgramDay] = []
          for try await row in group { saved.append(row) }
          days.removeAll(where: { $0.week == dstWeek })
          days.append(contentsOf: saved)
        }

      case .applyWeek(let srcWeek, let targets):
        for targetWeek in targets.sorted() {
          try await withThrowingTaskGroup(of: SDProgramDay.self) { group in
            for d in 1...template.lift_weekdays.count {
              let exercises = independentCopy(dayMap[dayKey(week: srcWeek, dayIndex: d)]?.exercises ?? [])
              group.addTask {
                try await supabase.upsertProgramDay(templateId: template.id, week: targetWeek, dayIndex: d, exercises: exercises)
              }
            }
            var saved: [SDProgramDay] = []
            for try await row in group { saved.append(row) }
            days.removeAll(where: { $0.week == targetWeek })
            days.append(contentsOf: saved)
          }
        }
      }
      days.sort { ($0.week, $0.day_index) < ($1.week, $1.day_index) }
      toastText = "Updated"
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func applyClearOperation(_ op: ProgramClearOperation) async {
    guard let supabase = appState.supabase else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      switch op {
      case .clearDay(let key):
        let saved = try await supabase.upsertProgramDay(templateId: template.id, week: key.week, dayIndex: key.dayIndex, exercises: [])
        days.removeAll(where: { $0.week == key.week && $0.day_index == key.dayIndex })
        days.append(saved)
      case .clearWeek(let week):
        try await withThrowingTaskGroup(of: SDProgramDay.self) { group in
          for d in 1...template.lift_weekdays.count {
            group.addTask {
              try await supabase.upsertProgramDay(templateId: template.id, week: week, dayIndex: d, exercises: [])
            }
          }
          var saved: [SDProgramDay] = []
          for try await row in group { saved.append(row) }
          days.removeAll(where: { $0.week == week })
          days.append(contentsOf: saved)
        }
      }
      days.sort { ($0.week, $0.day_index) < ($1.week, $1.day_index) }
      toastText = "Cleared"
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func duplicateTemplate() async {
    guard let supabase = appState.supabase else { return }
    isMutatingTemplate = true
    defer { isMutatingTemplate = false }
    do {
      let duplicate = try await supabase.duplicateProgramTemplate(template)
      onDuplicated(duplicate)
      toastText = "Program duplicated"
    } catch {
      errorText = "The program could not be duplicated. \(error.localizedDescription)"
    }
  }

  private func independentCopy(_ exercises: [SDExercise]) -> [SDExercise] {
    exercises.map {
      SDExercise(id: UUID(), name: $0.name, sets: $0.sets, reps: $0.reps, unit: $0.unit, notes: $0.notes)
    }
  }

  private func deleteTemplate() async {
    guard let supabase = appState.supabase else { return }
    isMutatingTemplate = true
    defer { isMutatingTemplate = false }
    do {
      try await supabase.deleteProgramTemplate(id: template.id)
      onDeleted()
      dismiss()
    } catch {
      errorText = "This program could not be deleted. End any player assignments using it, then try again."
    }
  }
}

private struct GridCellKey: Identifiable, Hashable {
  let id = UUID()
  let week: Int
  let dayIndex: Int
}

// MARK: - Grid view

struct ProgramTemplateGridView: View {
  let template: SDProgramTemplate
  let dayMap: [String: SDProgramDay]
  let onSelectCell: (Int, Int) -> Void
  let onCopyCell: (Int, Int) -> Void
  let onClearCell: (Int, Int) -> Void

  private let spacing: CGFloat = 10

  var body: some View {
    VStack(spacing: spacing) {
      headerRow
      ForEach(1...template.weeks, id: \.self) { week in
        weekRow(week)
      }
    }
  }

  private var headerRow: some View {
    HStack(spacing: spacing) {
      Text("Week")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .frame(width: 58, alignment: .leading)
      ForEach(1...template.lift_weekdays.count, id: \.self) { dayIndex in
        let weekday = template.lift_weekdays[safe: dayIndex - 1] ?? 1
        Text("Day \(dayIndex)\n(\(weekdayShort(weekday)))")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .frame(maxWidth: .infinity)
      }
    }
  }

  private func weekRow(_ week: Int) -> some View {
    HStack(spacing: spacing) {
      Text("W\(week)")
        .font(.subheadline.weight(.semibold))
        .frame(width: 58, alignment: .leading)
        .foregroundStyle(.secondary)

      ForEach(1...template.lift_weekdays.count, id: \.self) { dayIndex in
        let key = "\(week)-\(dayIndex)"
        let day = dayMap[key]
        Button {
          onSelectCell(week, dayIndex)
        } label: {
          ProgramGridCell(day: day)
        }
        .buttonStyle(.plain)
        .contextMenu {
          Button("Edit") { onSelectCell(week, dayIndex) }
          Divider()
          Button("Copy…") { onCopyCell(week, dayIndex) }
          Button("Clear…", role: .destructive) { onClearCell(week, dayIndex) }
        }
      }
    }
  }

  private func weekdayShort(_ i: Int) -> String {
    [1: "Mon", 2: "Tue", 3: "Wed", 4: "Thu", 5: "Fri", 6: "Sat", 7: "Sun"][i] ?? "Mon"
  }
}

private struct ProgramGridCell: View {
  let day: SDProgramDay?

  var body: some View {
    let names = (day?.exercises ?? []).map(\.name).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    VStack(alignment: .leading, spacing: 6) {
      if names.isEmpty {
        Text("—")
          .font(.headline)
          .foregroundStyle(DHDTheme.textSecondary)
        Text("Add")
          .font(.caption.weight(.semibold))
          .foregroundStyle(DHDTheme.accent.opacity(0.95))
      } else {
        Text(names.prefix(2).joined(separator: " • "))
          .font(.subheadline.weight(.semibold))
          .lineLimit(2)
          .foregroundStyle(DHDTheme.textPrimary)
        if names.count > 2 {
          Text("+\(names.count - 2) more")
            .font(.caption)
            .foregroundStyle(DHDTheme.textSecondary)
        }
      }
    }
    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
    .padding(10)
    .background(
      RoundedRectangle(cornerRadius: 14)
        .fill(DHDTheme.surfaceElevated)
        .shadow(color: DHDTheme.macShadowColor, radius: 10, x: 0, y: 5)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 14)
        .strokeBorder(DHDTheme.separator.opacity(0.35), lineWidth: 1)
    )
  }
}

// MARK: - Copy/Clear sheets

private enum ProgramCopyOperation {
  case copyDay(src: (week: Int, dayIndex: Int), dst: (week: Int, dayIndex: Int))
  case copyWeek(srcWeek: Int, dstWeek: Int)
  case applyWeek(srcWeek: Int, targets: Set<Int>)
}

private enum ProgramCopyPrefill: Equatable {
  case day(srcWeek: Int, srcDay: Int)
  case week(srcWeek: Int)
}

private struct ProgramCopySheet: View {
  @Environment(\.dismiss) private var dismiss
  let template: SDProgramTemplate
  let prefill: ProgramCopyPrefill?
  let onApply: (ProgramCopyOperation) -> Void

  @State private var mode: Int = 0

  @State private var srcWeek = 1
  @State private var srcDay = 1
  @State private var dstWeek = 1
  @State private var dstDay = 1

  @State private var srcWeekOnly = 1
  @State private var dstWeekOnly = 2

  @State private var applySrcWeek = 1
  @State private var applyTargets: Set<Int> = []

  var body: some View {
    NavigationStack {
      Form {
        Picker("Action", selection: $mode) {
          Text("Copy Day").tag(0)
          Text("Copy Week").tag(1)
          Text("Apply Week").tag(2)
        }
        .pickerStyle(.segmented)

        if mode == 0 {
          Section("Source") {
            Picker("Week", selection: $srcWeek) { ForEach(1...template.weeks, id: \.self) { Text("Week \($0)").tag($0) } }
            Picker("Day", selection: $srcDay) { ForEach(1...template.lift_weekdays.count, id: \.self) { Text("Day \($0)").tag($0) } }
          }
          Section("Destination") {
            Picker("Week", selection: $dstWeek) { ForEach(1...template.weeks, id: \.self) { Text("Week \($0)").tag($0) } }
            Picker("Day", selection: $dstDay) { ForEach(1...template.lift_weekdays.count, id: \.self) { Text("Day \($0)").tag($0) } }
          }
          Section {
            Text("This overwrites the destination day.")
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
        } else if mode == 1 {
          Section("Source") {
            Picker("Week", selection: $srcWeekOnly) { ForEach(1...template.weeks, id: \.self) { Text("Week \($0)").tag($0) } }
          }
          Section("Destination") {
            Picker("Week", selection: $dstWeekOnly) { ForEach(1...template.weeks, id: \.self) { Text("Week \($0)").tag($0) } }
          }
          Section {
            Text("This overwrites every day in the destination week.")
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
        } else {
          Section("Source") {
            Picker("Week", selection: $applySrcWeek) { ForEach(1...template.weeks, id: \.self) { Text("Week \($0)").tag($0) } }
          }
          Section("Target weeks") {
            ForEach(1...template.weeks, id: \.self) { w in
              if w != applySrcWeek {
                Toggle("Week \(w)", isOn: Binding(
                  get: { applyTargets.contains(w) },
                  set: { on in if on { applyTargets.insert(w) } else { applyTargets.remove(w) } }
                ))
              }
            }
          }
          Section {
            Text("This overwrites every selected target week.")
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
        }
      }
      .navigationTitle("Copy")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Apply") {
            let op: ProgramCopyOperation
            if mode == 0 {
              op = .copyDay(src: (srcWeek, srcDay), dst: (dstWeek, dstDay))
            } else if mode == 1 {
              op = .copyWeek(srcWeek: srcWeekOnly, dstWeek: dstWeekOnly)
            } else {
              op = .applyWeek(srcWeek: applySrcWeek, targets: applyTargets)
            }
            onApply(op)
            dismiss()
          }
          .disabled(!canApply)
        }
      }
    }
    .onAppear {
      dstWeekOnly = min(template.weeks, 2)
      if let prefill {
        switch prefill {
        case .day(let w, let d):
          mode = 0
          srcWeek = min(max(1, w), template.weeks)
          srcDay = min(max(1, d), max(1, template.lift_weekdays.count))
          // default destination: same week, next day (or same day if only 1)
          dstWeek = srcWeek
          dstDay = min(max(1, srcDay + 1), max(1, template.lift_weekdays.count))
        case .week(let w):
          mode = 1
          srcWeekOnly = min(max(1, w), template.weeks)
          dstWeekOnly = min(template.weeks, max(1, w == 1 ? 2 : 1))
        }
      }
    }
  }

  private var canApply: Bool {
    if mode == 0 { return !(srcWeek == dstWeek && srcDay == dstDay) }
    if mode == 1 { return srcWeekOnly != dstWeekOnly }
    return !applyTargets.isEmpty
  }
}

private enum ProgramClearOperation {
  case clearDay(key: (week: Int, dayIndex: Int))
  case clearWeek(week: Int)
}

private enum ProgramClearPrefill: Equatable {
  case day(week: Int, day: Int)
  case week(week: Int)
}

private struct ProgramClearSheet: View {
  @Environment(\.dismiss) private var dismiss
  let template: SDProgramTemplate
  let prefill: ProgramClearPrefill?
  let onApply: (ProgramClearOperation) -> Void

  @State private var mode: Int = 0
  @State private var week = 1
  @State private var day = 1

  var body: some View {
    NavigationStack {
      Form {
        Picker("Action", selection: $mode) {
          Text("Clear Day").tag(0)
          Text("Clear Week").tag(1)
        }
        .pickerStyle(.segmented)

        if mode == 0 {
          Picker("Week", selection: $week) { ForEach(1...template.weeks, id: \.self) { Text("Week \($0)").tag($0) } }
          Picker("Day", selection: $day) { ForEach(1...template.lift_weekdays.count, id: \.self) { Text("Day \($0)").tag($0) } }
        } else {
          Picker("Week", selection: $week) { ForEach(1...template.weeks, id: \.self) { Text("Week \($0)").tag($0) } }
        }

        Text("This removes all exercises from the selected scope.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
      .navigationTitle("Clear")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Clear", role: .destructive) {
            if mode == 0 {
              onApply(.clearDay(key: (week, day)))
            } else {
              onApply(.clearWeek(week: week))
            }
            dismiss()
          }
        }
      }
    }
    .onAppear {
      if let prefill {
        switch prefill {
        case .day(let w, let d):
          mode = 0
          week = min(max(1, w), template.weeks)
          day = min(max(1, d), max(1, template.lift_weekdays.count))
        case .week(let w):
          mode = 1
          week = min(max(1, w), template.weeks)
        }
      }
    }
  }
}

// MARK: - Helpers

private extension Array {
  subscript(safe index: Int) -> Element? {
    guard index >= 0, index < count else { return nil }
    return self[index]
  }
}
