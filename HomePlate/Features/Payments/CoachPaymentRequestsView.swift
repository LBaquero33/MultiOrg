import SwiftUI

/// Team-scoped payment requests for active head coaches. Stripe account setup
/// and organization analytics remain owner/admin-only elsewhere in the app.
struct CoachPaymentRequestsView: View {
  @EnvironmentObject private var appState: AppState
  @State private var players: [SDPaymentRequestEligiblePlayer] = []
  @State private var requests: [SDPaymentRequest] = []
  @State private var isLoading = false
  @State private var isPresentingCreate = false
  @State private var errorText: String?

  var body: some View {
    HPListScreenLayout {
      HPWorkspaceHeader(
        "Payment Requests",
        context: "Head coach team scope"
      ) {
        Button {
          isPresentingCreate = true
        } label: {
          Label("New request", systemImage: "plus")
        }
        .buttonStyle(.borderedProminent)
        .disabled(players.isEmpty || isLoading)
      }
    } controls: {
      HPCard {
        HStack(alignment: .top, spacing: HP.Space.sm) {
            Image(systemName: "person.2.fill")
            .foregroundStyle(HP.Color.accent)
          Text("Only active players on teams where you are assigned as head coach are available.")
            .font(HP.Font.caption)
            .foregroundStyle(HP.Color.textMuted)
        }
      }
    } results: { _ in
      VStack(alignment: .leading, spacing: HP.Space.md) {
        if let errorText {
          HPCard { HPErrorState(message: errorText, onRetry: { Task { await reload() } }) }
        } else if isLoading && requests.isEmpty {
          HPCard { HPLoadingState(text: "Loading payment requests…") }
        } else if requests.isEmpty {
          HPCard {
            HPEmptyState(
              title: "No payment requests",
              message: "Create a request when a player on one of your teams owes an organization fee.",
              systemImage: "creditcard"
            )
          }
        } else {
          HPSectionHeader("Requests") {
            HPStatusBadge(text: "\(requests.count)", kind: .neutral)
          }
          ForEach(requests) { request in
            requestCard(request)
          }
        }
      }
    }
    .navigationTitle("Payments")
    .refreshable { await reload() }
    .task(id: appState.activeOrgId) { await reload() }
    .sheet(isPresented: $isPresentingCreate) {
      CoachPaymentRequestCreateSheet(players: players) { draft in
        await create(draft)
      }
    }
  }

  private func requestCard(_ request: SDPaymentRequest) -> some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HStack(alignment: .top) {
          VStack(alignment: .leading, spacing: 3) {
            Text(request.title).font(HP.Font.headline)
            Text(request.player_name ?? "Player")
              .font(HP.Font.caption)
              .foregroundStyle(HP.Color.textMuted)
          }
          Spacer()
          HPStatusBadge(text: request.status.rawValue.capitalized, kind: statusKind(request.status))
        }
        HStack {
          Text(request.money?.formatted() ?? "Amount unavailable")
            .font(HP.Font.body.weight(.semibold))
          Spacer()
          if let due = request.due_date { Text("Due \(due)") }
        }
        .font(HP.Font.caption)
        .foregroundStyle(HP.Color.textMuted)
        if let description = request.description, !description.isEmpty {
          Text(description).font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
        }
        if request.status == .open {
          Button("Cancel request", role: .destructive) {
            Task { await cancel(request) }
          }
          .buttonStyle(.bordered)
        }
      }
    }
  }

  private func statusKind(_ status: SDPaymentRequestStatus) -> HPStatusKind {
    switch status {
    case .open: .warning
    case .paid: .success
    case .canceled: .neutral
    }
  }

  private func reload() async {
    guard let service = appState.supabase, let orgId = appState.activeOrgId else {
      players = []
      requests = []
      errorText = "Choose an organization to view payment requests."
      return
    }
    isLoading = true
    errorText = nil
    defer { isLoading = false }
    do {
      async let loadedPlayers = service.listEligiblePaymentRequestPlayers(orgId: orgId)
      async let loadedRequests = service.listManagedPaymentRequests(orgId: orgId)
      players = try await loadedPlayers
      requests = try await loadedRequests
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func create(_ submittedDraft: SDPaymentRequestCreateDraft) async -> Bool {
    guard let service = appState.supabase, let orgId = appState.activeOrgId else { return false }
    var draft = submittedDraft
    guard let payload = draft.prepareCreatePayload(orgId: orgId) else { return false }
    do {
      _ = try await service.createPaymentRequests(payload: payload)
      draft.completeOperation(idempotencyKey: payload.idempotency_key)
      await reload()
      return true
    } catch {
      errorText = error.localizedDescription
      return false
    }
  }

  private func cancel(_ request: SDPaymentRequest) async {
    guard let service = appState.supabase, let orgId = appState.activeOrgId else { return }
    do {
      _ = try await service.cancelPaymentRequest(orgId: orgId, requestId: request.id)
      await reload()
    } catch {
      errorText = error.localizedDescription
    }
  }
}

private struct CoachPaymentRequestCreateSheet: View {
  @Environment(\.dismiss) private var dismiss
  let players: [SDPaymentRequestEligiblePlayer]
  let onCreate: (SDPaymentRequestCreateDraft) async -> Bool
  @State private var draft = SDPaymentRequestCreateDraft()
  @State private var isSubmitting = false
  @State private var errorText: String?

  var body: some View {
    NavigationStack {
      Form {
        Section("Players") {
          ForEach(players) { player in
            Toggle(
              player.displayName,
              isOn: Binding(
                get: { draft.selectedPlayerUserIds.contains(player.id) },
                set: { selected in
                  if selected { draft.selectedPlayerUserIds.insert(player.id) }
                  else { draft.selectedPlayerUserIds.remove(player.id) }
                }
              )
            )
          }
        }
        Section("Request") {
          TextField("Title", text: $draft.title)
          TextField("Amount (USD)", text: $draft.amountDollars)
          Toggle("Include due date", isOn: $draft.includesDueDate)
          if draft.includesDueDate {
            DatePicker("Due date", selection: $draft.dueDate, displayedComponents: .date)
          }
          TextField("Description (optional)", text: $draft.description, axis: .vertical)
        }
        if let message = errorText ?? draft.validationError {
          Section { Text(message).foregroundStyle(HP.Color.danger) }
        }
      }
      .navigationTitle("New Payment Request")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(isSubmitting ? "Creating…" : "Create") {
            Task {
              isSubmitting = true
              errorText = nil
              if await onCreate(draft) { dismiss() }
              else { errorText = "The payment request could not be created." }
              isSubmitting = false
            }
          }
          .disabled(!draft.isValid || isSubmitting)
        }
      }
    }
  }
}
