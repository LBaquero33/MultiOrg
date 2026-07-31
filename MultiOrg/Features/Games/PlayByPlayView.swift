import SwiftUI

struct PlayByPlayView: View {
  @EnvironmentObject private var appState: AppState
  let game: SDGame

  @State private var events: [SDScoringEvent] = []
  @State private var audit: [SDGameAuditEntry] = []
  @State private var errorText: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      if events.isEmpty {
        Text("No scoring events have been recorded.")
          .foregroundStyle(DHDTheme.textSecondary)
      }
      ForEach(events) { event in
        HStack(alignment: .top, spacing: 10) {
          Text("\(event.sequence)")
            .font(.caption.monospacedDigit().bold())
            .frame(width: 30)
          VStack(alignment: .leading, spacing: 2) {
            Text(title(event.event_type)).font(.subheadline.weight(.semibold))
            Text(event.occurred_at.formatted(date: .omitted, time: .standard))
              .font(.caption).foregroundStyle(DHDTheme.textSecondary)
          }
          Spacer()
          Text("v\(event.game_version)")
            .font(.caption.monospacedDigit()).foregroundStyle(DHDTheme.textSecondary)
        }
        Divider()
      }
      if !audit.isEmpty {
        DisclosureGroup("Audit history") {
          ForEach(audit) { entry in
            HStack {
              Text(title(entry.action))
              Spacer()
              Text(entry.created_at.formatted(date: .abbreviated, time: .shortened))
                .foregroundStyle(DHDTheme.textSecondary)
            }
            .font(.caption)
          }
        }
      }
    }
    .task(id: game.game_version) { await load() }
    .alert("Play-by-play unavailable", isPresented: Binding(
      get: { errorText != nil }, set: { if !$0 { errorText = nil } }
    )) { Button("OK", role: .cancel) {} } message: { Text(errorText ?? "") }
  }

  private func load() async {
    guard let service = appState.supabase, let orgId = appState.activeOrgId else { return }
    do {
      async let eventLoad = service.listScoringEvents(gameId: game.id, organizationId: orgId)
      async let auditLoad = service.listGameAudit(gameId: game.id, organizationId: orgId)
      events = try await eventLoad
      audit = (try? await auditLoad) ?? []
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func title(_ value: SDScoringEventType) -> String { title(value.rawValue) }

  private func title(_ value: String) -> String {
    value.replacingOccurrences(of: "_", with: " ").capitalized
  }
}
