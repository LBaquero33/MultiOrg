import SwiftUI

struct SDPlayerTestingView: View {
  @EnvironmentObject private var appState: AppState

  @State private var entries: [SDTestingEntry] = []
  @State private var isLoading = false
  @State private var showAdd = false
  @State private var errorText: String?

  var body: some View {
    NavigationStack {
      HPListScreenLayout {
        HPWorkspaceHeader("Testing", context: "Player testing history") {
          HPButton(title: "Add entry", systemImage: "plus",
                   variant: .primary, size: .sm) {
            showAdd = true
          }
        }
      } controls: {
        HPCard {
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
                .accessibilityLabel("Refreshing testing entries")
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
              HPLoadingState(text: "Loading testing entries…")
            }

            if errorText != nil {
              HPErrorState(
                message: "We couldn’t load testing entries. Check your connection and try again.",
                onRetry: { Task { await reload() } }
              )
            }

            if entries.isEmpty, !isLoading {
              if errorText == nil {
                HPEmptyState(
                  title: "No testing entries yet",
                  message: "Add your first testing entry to begin tracking progress.",
                  systemImage: "list.bullet.clipboard",
                  actionTitle: "Add entry",
                  actionIsPrimary: false,
                  action: { showAdd = true }
                )
              }
            } else if !entries.isEmpty {
              HPTable(
                columns: [
                  HPColumn(title: "Date"),
                  HPColumn(title: "Measurements"),
                ],
                rows: entryRows,
                layout: context.tableLayout
              )
            }
          }
        }
      }
      .navigationTitle("Testing")
      .toolbar {
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
      .task {
        await reload()
      }
    }
  }

  private var entryRows: [HPTableRow] {
    entries.map { entry in
      HPTableRow(cells: [entry.entry_date, summary(entry)])
    }
  }

  private func reload() async {
    guard let supabase = appState.supabase else { return }
    errorText = nil
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

  private func summary(_ entry: SDTestingEntry) -> String {
    var parts: [String] = []
    if let value = entry.squat_1rm { parts.append("Squat \(fmt(value))") }
    if let value = entry.bench_1rm { parts.append("Bench \(fmt(value))") }
    if let value = entry.deadlift_1rm { parts.append("Deadlift \(fmt(value))") }
    if let value = entry.max_exit_velo { parts.append("MaxEV \(fmt(value))") }
    if let value = entry.avg_exit_velo { parts.append("AvgEV \(fmt(value))") }
    if parts.isEmpty { return "—" }
    return parts.joined(separator: " • ")
  }

  private func fmt(_ value: Double) -> String {
    if value.rounded() == value { return String(Int(value)) }
    return String(format: "%.1f", value)
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
      HPFormScreenLayout { _ in
        HPWorkspaceHeader("Add testing entry", context: "Player testing history")
      } sections: { _ in
        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.md) {
            HPSectionHeader("Date")
            DatePicker("Entry date", selection: $date, displayedComponents: .date)
              .font(HP.Font.callout)
              .foregroundStyle(HP.Color.text)
              .tint(HP.Color.accent)
          }
        }

        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.md) {
            HPSectionHeader("Body")
            HPFormField(label: "Height (in)", text: $heightIn,
                        placeholder: "Optional")
              .modifier(NumericKeyboard())
            HPFormField(label: "Weight (lb)", text: $weightLb,
                        placeholder: "Optional")
              .modifier(NumericKeyboard())
          }
        }

        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.md) {
            HPSectionHeader("Strength")
            HPFormField(label: "Squat 1RM", text: $squat, placeholder: "Optional")
              .modifier(NumericKeyboard())
            HPFormField(label: "Bench 1RM", text: $bench, placeholder: "Optional")
              .modifier(NumericKeyboard())
            HPFormField(label: "Deadlift 1RM", text: $deadlift, placeholder: "Optional")
              .modifier(NumericKeyboard())
          }
        }

        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.md) {
            HPSectionHeader("Hitting")
            HPFormField(label: "Max EV (mph)", text: $maxEV, placeholder: "Optional")
              .modifier(NumericKeyboard())
            HPFormField(label: "Avg EV (mph)", text: $avgEV, placeholder: "Optional")
              .modifier(NumericKeyboard())
          }
        }

        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.md) {
            HPSectionHeader("Mobility differences")
            HPFormField(label: "Hip ER difference", text: $hipER, placeholder: "Optional")
              .modifier(NumericKeyboard())
            HPFormField(label: "Hip IR difference", text: $hipIR, placeholder: "Optional")
              .modifier(NumericKeyboard())
            HPFormField(label: "Shoulder IR difference", text: $shoulderIR, placeholder: "Optional")
              .modifier(NumericKeyboard())
            HPFormField(label: "Shoulder ER difference", text: $shoulderER, placeholder: "Optional")
              .modifier(NumericKeyboard())
          }
        }

        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.md) {
            HPSectionHeader("Notes")
            HPFormField(label: "Notes (optional)", text: $notes,
                        kind: .multiline, placeholder: "Anything to remember")
          }
        }
      } primaryAction: { context in
        HPButton(title: "Save entry", systemImage: "checkmark",
                 variant: .primary, size: .lg,
                 isLoading: isSaving,
                 fullWidth: context.isAccessibilitySize) {
          Task { await save() }
        }
      } secondaryAction: { context in
        HPButton(title: "Cancel", variant: .secondary, size: .lg,
                 fullWidth: context.isAccessibilitySize) {
          dismiss()
        }
      }
      .navigationTitle("Add entry")
      .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { _ in errorText = nil })) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(errorText ?? "")
      }
    }
  }

  private func toDouble(_ string: String) -> Double? {
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return nil }
    return Double(trimmed)
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
