import SwiftUI

/// Coach-facing Testing tab with add/edit (Shiny parity).
struct CoachPlayerTestingCRUDView: View {
  @EnvironmentObject private var appState: AppState
  let player: Profile
  let canManagePlayer: Bool

  @State private var entries: [SDTestingEntry] = []
  @State private var isLoading = false
  @State private var showAdd = false
  @State private var editingEntry: SDTestingEntry?
  @State private var errorText: String?

  var body: some View {
    HPListScreenLayout {
      HPWorkspaceHeader(
        "Testing",
        orgLabel: activeOrganizationName,
        context: player.displayName
      ) {
        HPButton(
          title: "Add entry",
          systemImage: "plus",
          variant: .primary,
          size: .sm,
          action: { showAdd = true }
        )
        .disabled(!canManagePlayer)
      }
    } controls: {
      HPCard {
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          HStack(spacing: HP.Space.sm) {
            Image(systemName: "list.bullet.clipboard")
              .foregroundStyle(HP.Color.accent)
              .accessibilityHidden(true)
            Text("\(entries.count) \(entries.count == 1 ? "entry" : "entries")")
              .font(HP.Font.callout)
              .foregroundStyle(HP.Color.text)
            Spacer(minLength: 0)
            if isLoading {
              HPProgressIndicator(style: .spinner)
                .accessibilityLabel("Loading testing entries")
            }
          }

          if !canManagePlayer {
            Label("Your organization limits testing changes to players on your assigned team.", systemImage: "lock.fill")
              .font(HP.Font.caption)
              .foregroundStyle(HP.Color.warning)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
    } results: { context in
      HPCard {
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          HPSectionHeader("Entries") {
            HPStatusBadge(text: "\(entries.count)", kind: .neutral)
          }

          if isLoading {
            HPLoadingState(text: "Loading…")
          } else if entries.isEmpty {
            HPEmptyState(
              title: "No testing entries yet.",
              message: "Testing entries for \(player.displayName) will appear here.",
              systemImage: "list.bullet.clipboard"
            )
          } else {
            if context.tableLayout == .columns {
              testingColumnHeader
            }

            ForEach(entries) { entry in
              Button {
                editingEntry = entry
              } label: {
                testingEntryRow(entry, stacked: context.tableLayout != .columns)
              }
              .buttonStyle(.plain)
              .disabled(!canManagePlayer)
              .accessibilityHint(
                canManagePlayer
                  ? "Opens the testing entry editor"
                  : "Testing changes are unavailable for this player"
              )

              if entry.id != entries.last?.id {
                Divider().overlay(HP.Color.border.opacity(0.5))
              }
            }
          }
        }
      }
    }
    .sheet(isPresented: $showAdd) {
      TestingEntryFormSheet(
        title: "Add entry",
        playerId: player.id,
        existing: nil
      ) { saved in
        entries.removeAll(where: { $0.entry_date == saved.entry_date })
        entries.insert(saved, at: 0)
      }
      .environmentObject(appState)
    }
    .sheet(item: $editingEntry) { existing in
      TestingEntryFormSheet(
        title: "Edit entry",
        playerId: player.id,
        existing: existing
      ) { saved in
        entries.removeAll(where: { $0.entry_date == saved.entry_date })
        entries.insert(saved, at: 0)
      }
      .environmentObject(appState)
    }
    .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { _ in errorText = nil })) {
      Button("OK", role: .cancel) {}
    } message: { Text(errorText ?? "") }
    .task { await reload() }
  }

  private var activeOrganizationName: String {
    if let organizationId = appState.activeOrgId,
       let organization = appState.availableOrganizations.first(where: { $0.id == organizationId }) {
      return organization.displayName
    }
    return appState.activeOrgSettings?.display_name
      ?? appState.activeOrgSettings?.short_name
      ?? "Home Plate"
  }

  private var testingColumnHeader: some View {
    HStack(spacing: HP.Space.sm) {
      Text("DATE")
        .frame(width: 140, alignment: .leading)
      Text("MEASUREMENTS")
        .frame(maxWidth: .infinity, alignment: .leading)
      Color.clear
        .frame(width: 20, height: 1)
        .accessibilityHidden(true)
    }
    .font(HP.Font.eyebrow)
    .tracking(HP.Font.eyebrowTracking)
    .foregroundStyle(HP.Color.textMuted)
    .padding(.vertical, 6)
  }

  @ViewBuilder
  private func testingEntryRow(_ entry: SDTestingEntry, stacked: Bool) -> some View {
    if stacked {
      VStack(alignment: .leading, spacing: HP.Space.xs) {
        Text(entry.entry_date)
          .font(HP.Font.headline)
          .foregroundStyle(HP.Color.text)
        Text(summary(entry))
          .font(HP.Font.caption)
          .foregroundStyle(HP.Color.textMuted)
          .fixedSize(horizontal: false, vertical: true)
        if canManagePlayer {
          Label("Edit entry", systemImage: "pencil")
            .font(HP.Font.caption.weight(.semibold))
            .foregroundStyle(HP.Color.accent)
        }
      }
      .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
      .contentShape(Rectangle())
    } else {
      HStack(spacing: HP.Space.sm) {
        Text(entry.entry_date)
          .font(HP.Font.callout.weight(.semibold))
          .foregroundStyle(HP.Color.text)
          .frame(width: 140, alignment: .leading)
        Text(summary(entry))
          .font(HP.Font.caption)
          .foregroundStyle(HP.Color.textMuted)
          .lineLimit(2)
          .frame(maxWidth: .infinity, alignment: .leading)
        Image(systemName: "chevron.right")
          .font(.caption.weight(.semibold))
          .foregroundStyle(HP.Color.textMuted)
          .frame(width: 20)
          .accessibilityHidden(true)
      }
      .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
      .contentShape(Rectangle())
    }
  }

  private func reload() async {
    guard let supabase = appState.supabase else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      entries = try await supabase.listTestingEntries(playerId: player.id)
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func summary(_ e: SDTestingEntry) -> String {
    var parts: [String] = []
    if let v = e.squat_1rm { parts.append("Sq \(fmt(v))") }
    if let v = e.bench_1rm { parts.append("Bn \(fmt(v))") }
    if let v = e.deadlift_1rm { parts.append("Dl \(fmt(v))") }
    if let v = e.max_exit_velo { parts.append("MaxEV \(fmt(v))") }
    if let v = e.avg_exit_velo { parts.append("AvgEV \(fmt(v))") }
    return parts.isEmpty ? "—" : parts.joined(separator: " • ")
  }

  private func fmt(_ v: Double) -> String {
    if v.rounded() == v { return String(Int(v)) }
    return String(format: "%.1f", v)
  }
}

private struct TestingEntryFormSheet: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var appState: AppState

  let title: String
  let playerId: UUID
  let existing: SDTestingEntry?
  let onSaved: (SDTestingEntry) -> Void

  @State private var date: Date = Date()
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
      HPFormScreenLayout { _ in
        HPWorkspaceHeader(
          title,
          orgLabel: activeOrganizationName,
          context: existing == nil ? "New testing entry" : "Testing entry • \(existing?.entry_date ?? "")"
        )
      } sections: { _ in
        dateSection
        bodySection
        strengthSection
        hittingSection
        mobilitySection
        notesSection
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
        .disabled(isSaving)
      } secondaryAction: { context in
        HPButton(
          title: "Cancel",
          variant: .secondary,
          size: .lg,
          fullWidth: context.isAccessibilitySize,
          action: { dismiss() }
        )
      }
      .navigationTitle(title)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
            #if os(macOS)
            .keyboardShortcut(.cancelAction)
            #endif
        }
      }
      .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { _ in errorText = nil })) {
        Button("OK", role: .cancel) {}
      } message: { Text(errorText ?? "") }
      .task { preload() }
    }
  }

  private var activeOrganizationName: String {
    if let organizationId = appState.activeOrgId,
       let organization = appState.availableOrganizations.first(where: { $0.id == organizationId }) {
      return organization.displayName
    }
    return appState.activeOrgSettings?.display_name
      ?? appState.activeOrgSettings?.short_name
      ?? "Home Plate"
  }

  private var dateSection: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Date")
        DatePicker("Entry date", selection: $date, displayedComponents: .date)
          .font(HP.Font.body)
          .foregroundStyle(HP.Color.text)
          .tint(HP.Color.accent)
      }
    }
  }

  private var bodySection: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.md) {
        HPSectionHeader("Body")
        numericField("Height (in)", text: $heightIn)
        numericField("Weight (lb)", text: $weightLb)
      }
    }
  }

  private var strengthSection: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.md) {
        HPSectionHeader("Strength")
        numericField("Squat 1RM", text: $squat)
        numericField("Bench 1RM", text: $bench)
        numericField("Deadlift 1RM", text: $deadlift)
      }
    }
  }

  private var hittingSection: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.md) {
        HPSectionHeader("Hitting")
        numericField("Max EV (mph)", text: $maxEV)
        numericField("Avg EV (mph)", text: $avgEV)
      }
    }
  }

  private var mobilitySection: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.md) {
        HPSectionHeader("Mobility diffs")
        numericField("Hip ER difference", text: $hipER)
        numericField("Hip IR difference", text: $hipIR)
        numericField("Shoulder IR difference", text: $shoulderIR)
        numericField("Shoulder ER difference", text: $shoulderER)
      }
    }
  }

  private var notesSection: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Notes")
        HPFormField(
          label: "Notes (optional)",
          text: $notes,
          kind: .multiline,
          placeholder: "Notes (optional)"
        )
      }
    }
  }

  private func numericField(_ label: String, text: Binding<String>) -> some View {
    HPFormField(label: label, text: text, placeholder: label)
      .modifier(NumericKeyboard())
  }

  private func preload() {
    guard let existing else { return }
    date = DateUtils.fromISODate(existing.entry_date) ?? Date()
    heightIn = fmt(existing.height_in)
    weightLb = fmt(existing.weight_lb)
    squat = fmt(existing.squat_1rm)
    bench = fmt(existing.bench_1rm)
    deadlift = fmt(existing.deadlift_1rm)
    maxEV = fmt(existing.max_exit_velo)
    avgEV = fmt(existing.avg_exit_velo)
    hipER = fmt(existing.hip_er_diff)
    hipIR = fmt(existing.hip_ir_diff)
    shoulderIR = fmt(existing.shoulder_ir_diff)
    shoulderER = fmt(existing.shoulder_er_diff)
    notes = existing.notes ?? ""
  }

  private func toDouble(_ s: String) -> Double? {
    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    if t.isEmpty { return nil }
    return Double(t)
  }

  private func fmt(_ v: Double?) -> String {
    guard let v else { return "" }
    if v.rounded() == v { return String(Int(v)) }
    return String(format: "%.1f", v)
  }

  private func save() async {
    guard let supabase = appState.supabase else { return }
    isSaving = true
    defer { isSaving = false }
    do {
      let create = SDTestingEntryCreate(
        org_id: appState.activeOrgId,
        player_id: playerId,
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
