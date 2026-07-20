import SwiftUI

struct CoachPlayerDailyLogsView: View {
  @EnvironmentObject private var appState: AppState
  let player: Profile

  @State private var logs: [SDDailyLog] = []
  @State private var isLoading = false
  @State private var errorText: String?

  var body: some View {
    HPListScreenLayout {
      HPWorkspaceHeader(
        "Daily logs",
        context: player.displayName
      )
    } controls: {
      HPCard {
        HStack(spacing: HP.Space.sm) {
          Image(systemName: "checklist")
            .foregroundStyle(HP.Color.accent)
            .accessibilityHidden(true)
          Text("\(logs.count) \(logs.count == 1 ? "day" : "days")")
            .font(HP.Font.callout)
            .foregroundStyle(HP.Color.text)
          Spacer(minLength: 0)
          if isLoading {
            HPProgressIndicator(style: .spinner)
              .accessibilityLabel("Loading daily logs")
          }
        }
      }
    } results: { _ in
      HPCard {
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          HPSectionHeader("Recent days") {
            HPStatusBadge(text: "\(logs.count)", kind: .neutral)
          }

          if isLoading {
            HPLoadingState(text: "Loading…")
          }

          if logs.isEmpty, !isLoading {
            HPEmptyState(
              title: "No daily logs yet",
              message: "Daily logs for \(player.displayName) will appear here.",
              systemImage: "checklist"
            )
          } else if !logs.isEmpty {
            VStack(alignment: .leading, spacing: HP.Space.xs) {
              ForEach(logs) { log in
                NavigationLink {
                  CoachPlayerDailyLogDetailView(player: player, dateISO: log.log_date)
                } label: {
                  HStack(spacing: HP.Space.sm) {
                    VStack(alignment: .leading, spacing: 4) {
                      Text(log.log_date)
                        .font(HP.Font.headline)
                        .foregroundStyle(HP.Color.text)
                      Text(summary(log))
                        .font(HP.Font.caption)
                        .foregroundStyle(HP.Color.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: HP.Space.sm)
                    Image(systemName: "chevron.right")
                      .font(.caption.weight(.semibold))
                      .foregroundStyle(HP.Color.textMuted)
                      .accessibilityHidden(true)
                  }
                  .frame(minHeight: 44)
                  .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(log.log_date), \(summary(log))")
              }
            }
          }
        }
      }
    }
    .navigationTitle("Daily logs")
    .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { _ in errorText = nil }))
    {
      Button("OK", role: .cancel) {}
    } message: {
      Text(errorText ?? "")
    }
    .task { await reload() }
  }

  private func reload() async {
    guard let supabase = appState.supabase else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      logs = try await supabase.listDailyLogs(playerId: player.id, limit: 60)
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func summary(_ l: SDDailyLog) -> String {
    var bits: [String] = []
    if let f = l.feel { bits.append("Feel \(f)") }
    if let v = l.got_video, v { bits.append("Video") }
    if let b = l.ate_breakfast, b { bits.append("Breakfast") }
    if let g = l.hit_daily_goals, g { bits.append("Goals") }
    if let p = l.stuck_to_process, p { bits.append("Process") }
    return bits.isEmpty ? "—" : bits.joined(separator: " • ")
  }
}

private struct CoachPlayerDailyLogDetailView: View {
  @EnvironmentObject private var appState: AppState
  let player: Profile
  let dateISO: String

  @State private var log: SDDailyLog?
  @State private var strength: [SDStrengthLog] = []
  @State private var isLoading = false
  @State private var errorText: String?

  var body: some View {
    HPDetailScreenLayout {
      HPWorkspaceHeader(
        "Daily log",
        context: "\(player.displayName) • \(dateISO)"
      )
    } metrics: {
      EmptyView()
    } details: {
      VStack(alignment: .leading, spacing: HP.Space.md) {
        if isLoading {
          HPCard {
            HPLoadingState(text: "Loading…")
          }
        }

        selfAssessmentCard

        if let comments = log?.comments, !comments.isEmpty || log?.feel != nil {
          liftNoteCard(comments: comments)
        }
      }
    } related: { _ in
      strengthLogsCard
    } primaryAction: {
      EmptyView()
    }
    .navigationTitle(dateISO)
    .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { _ in errorText = nil }))
    {
      Button("OK", role: .cancel) {}
    } message: {
      Text(errorText ?? "")
    }
    .task { await reload() }
  }

  private var selfAssessmentCard: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Self assessment")
        row("Got video", log?.got_video)
        row("Ate breakfast", log?.ate_breakfast)
        row("Hit daily goals", log?.hit_daily_goals)
        row("Stuck to process", log?.stuck_to_process)
        if let text = log?.fell_short, !text.isEmpty {
          Text("Fell short: \(text)")
            .font(HP.Font.callout)
            .foregroundStyle(HP.Color.text)
            .fixedSize(horizontal: false, vertical: true)
        }
        if let text = log?.excelled, !text.isEmpty {
          Text("Excelled: \(text)")
            .font(HP.Font.callout)
            .foregroundStyle(HP.Color.text)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
  }

  private func liftNoteCard(comments: String) -> some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Lift note")
        if let feel = log?.feel {
          Text("Feel: \(feel)")
            .font(HP.Font.callout)
            .foregroundStyle(HP.Color.text)
        }
        if !comments.isEmpty {
          Text(comments)
            .font(HP.Font.callout)
            .foregroundStyle(HP.Color.text)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
  }

  private var strengthLogsCard: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Strength logs") {
          HPStatusBadge(text: "\(strength.count)", kind: .neutral)
        }
        if strength.isEmpty {
          Text("No strength logs for this day.")
            .font(HP.Font.callout)
            .foregroundStyle(HP.Color.textMuted)
        } else {
          ForEach(strength) { strengthLog in
            VStack(alignment: .leading, spacing: 4) {
              Text(strengthLog.exercise_name)
                .font(HP.Font.headline)
                .foregroundStyle(HP.Color.text)
              if strengthLog.no_weight {
                Text("No weight • Sets completed: \(strengthLog.sets_completed ?? 0)")
                  .font(HP.Font.caption)
                  .foregroundStyle(HP.Color.textMuted)
              } else if let weights = strengthLog.set_weights_json, !weights.isEmpty {
                Text("Weights: " + weights.joined(separator: ", "))
                  .font(HP.Font.caption)
                  .foregroundStyle(HP.Color.textMuted)
                  .fixedSize(horizontal: false, vertical: true)
              } else {
                Text("No weights logged")
                  .font(HP.Font.caption)
                  .foregroundStyle(HP.Color.textMuted)
              }
              if let notes = strengthLog.notes, !notes.isEmpty {
                Text(notes)
                  .font(HP.Font.caption)
                  .foregroundStyle(HP.Color.textMuted)
                  .fixedSize(horizontal: false, vertical: true)
              }
            }
            .padding(.vertical, 4)
          }
        }
      }
    }
  }

  private func reload() async {
    guard let supabase = appState.supabase else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      log = try await supabase.fetchDailyLog(playerId: player.id, dateISO: dateISO)
      strength = try await supabase.fetchStrengthLogs(playerId: player.id, dateISO: dateISO)
    } catch {
      errorText = error.localizedDescription
    }
  }

  @ViewBuilder private func row(_ label: String, _ value: Bool?) -> some View {
    HStack {
      Text(label)
        .font(HP.Font.callout)
        .foregroundStyle(HP.Color.text)
      Spacer()
      if value == true {
        Image(systemName: "checkmark.circle.fill")
          .foregroundStyle(HP.Color.success)
          .accessibilityLabel("Yes")
      } else if value == false {
        Image(systemName: "xmark.circle.fill")
          .foregroundStyle(HP.Color.danger)
          .accessibilityLabel("No")
      } else {
        Text("—")
          .foregroundStyle(HP.Color.textMuted)
          .accessibilityLabel("Not reported")
      }
    }
  }
}
