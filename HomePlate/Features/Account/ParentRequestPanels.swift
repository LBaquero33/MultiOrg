import SwiftUI

/// Player-facing: request parent access (coach approves) + view linked parents.
struct PlayerParentRequestsPanel: View {
  @EnvironmentObject private var appState: AppState

  @State private var linkedParents: [(Profile, SDParentChildLink)] = []
  @State private var requests: [SDParentInviteRequest] = []
  @State private var isLoading = false
  @State private var errorText: String?
  @State private var loadErrorText: String?

  @State private var parentEmail: String = ""
  @State private var relationship: String = ""

  var body: some View {
    VStack(alignment: .leading, spacing: HP.Space.md) {
      if isLoading {
        HPLoadingState(text: "Loading parent access…")
      } else if let loadErrorText {
        HPErrorState(
          title: "Parent access unavailable",
          message: loadErrorText,
          onRetry: { Task { await reload() } }
        )
      }

      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Linked parents") {
          if !linkedParents.isEmpty {
            HPStatusBadge(text: "\(linkedParents.count)", kind: .neutral)
          }
        }

        if linkedParents.isEmpty, loadErrorText == nil {
          HPEmptyState(
            title: "No linked parents",
            message: "Approved parent and guardian links will appear here.",
            systemImage: "person.2"
          )
        } else {
          ForEach(linkedParents, id: \.0.id) { parent, link in
            HStack(alignment: .firstTextBaseline, spacing: HP.Space.sm) {
              Text(parent.displayName)
                .font(HP.Font.callout)
                .foregroundStyle(HP.Color.text)
                .fixedSize(horizontal: false, vertical: true)
              Spacer(minLength: HP.Space.sm)
              if let rel = link.relationship,
                 !rel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                HPStatusBadge(text: rel, kind: .info)
              }
            }
            .padding(.vertical, HP.Space.xs)
          }
        }
      }

      Divider().overlay(HP.Color.border.opacity(0.5))

      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Request parent access")
        Text("Enter a parent/guardian email. A coach will approve it before the parent can link.")
          .font(HP.Font.caption)
          .foregroundStyle(HP.Color.textMuted)
          .fixedSize(horizontal: false, vertical: true)

        HPFormField(
          label: "Parent email",
          text: $parentEmail,
          placeholder: "parent@example.com",
          isEnabled: !isLoading
        )
#if canImport(UIKit)
          .textInputAutocapitalization(.never)
#endif
          .autocorrectionDisabled()

        HPFormField(
          label: "Relationship (optional)",
          text: $relationship,
          placeholder: "Parent or guardian",
          isEnabled: !isLoading
        )

        HPButton(
          title: "Send request",
          systemImage: "paperplane",
          variant: .primary,
          size: .md,
          action: { Task { await submitRequest() } }
        )
        .disabled(
          isLoading || parentEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
      }

      Divider().overlay(HP.Color.border.opacity(0.5))

      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Requests") {
          if !requests.isEmpty {
            HPStatusBadge(text: "\(requests.count)", kind: .neutral)
          }
        }
        if requests.isEmpty, loadErrorText == nil {
          HPEmptyState(
            title: "No requests yet",
            message: "Parent access requests you send will appear here.",
            systemImage: "paperplane"
          )
        } else {
          ForEach(Array(requests.enumerated()), id: \.element.id) { index, request in
            ViewThatFits(in: .horizontal) {
              HStack(alignment: .top, spacing: HP.Space.sm) {
                requestDetails(request)
                Spacer(minLength: HP.Space.sm)
                requestActions(request)
              }
              VStack(alignment: .leading, spacing: HP.Space.sm) {
                requestDetails(request)
                requestActions(request, fullWidth: true)
              }
            }
            .padding(.vertical, HP.Space.xs)
            if index < requests.count - 1 {
              Divider().overlay(HP.Color.border.opacity(0.5))
            }
          }
        }
      }
    }
    .task { await reload() }
    .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { _ in errorText = nil })) {
      Button("OK", role: .cancel) {}
    } message: { Text(errorText ?? "") }
  }

  private func requestDetails(_ request: SDParentInviteRequest) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(request.email_norm)
        .font(HP.Font.callout)
        .foregroundStyle(HP.Color.text)
        .fixedSize(horizontal: false, vertical: true)
      HPStatusBadge(
        text: request.status.capitalized,
        kind: parentRequestStatusKind(request.status)
      )
      if let note = request.coach_note,
         !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        Text(note)
          .font(HP.Font.caption)
          .foregroundStyle(HP.Color.textMuted)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  @ViewBuilder
  private func requestActions(_ request: SDParentInviteRequest, fullWidth: Bool = false) -> some View {
    if request.status.lowercased() == "requested" {
      HPButton(
        title: "Cancel",
        variant: .destructive,
        size: .sm,
        fullWidth: fullWidth,
        action: { Task { await cancelRequest(id: request.id) } }
      )
      .disabled(isLoading)
    }
  }

  private func reload() async {
    guard let supabase = appState.supabase else { return }
    loadErrorText = nil
    isLoading = true
    defer { isLoading = false }
    do {
      let links = try await supabase.listMyParentLinksAsChild()
      let parentIds = links.map(\.parent_id)
      let parents = try await supabase.listProfiles(ids: parentIds)
      let map = Dictionary(uniqueKeysWithValues: parents.map { ($0.id, $0) })
      linkedParents = links.compactMap { link in
        guard let p = map[link.parent_id] else { return nil }
        return (p, link)
      }.sorted { $0.0.displayName < $1.0.displayName }

      requests = try await supabase.listMyParentInviteRequests()
    } catch {
      loadErrorText = error.localizedDescription
      errorText = error.localizedDescription
    }
  }

  private func submitRequest() async {
    guard let supabase = appState.supabase, let orgId = appState.activeOrgId else {
      errorText = "Choose an organization before requesting a parent invite."
      return
    }
    isLoading = true
    defer { isLoading = false }
    do {
      _ = try await supabase.createParentInviteRequest(
        orgId: orgId,
        parentEmail: parentEmail,
        relationship: relationship.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : relationship
      )
      parentEmail = ""
      relationship = ""
      await reload()
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func cancelRequest(id: UUID) async {
    guard let supabase = appState.supabase else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      try await supabase.cancelParentInviteRequest(requestId: id)
      await reload()
    } catch {
      errorText = error.localizedDescription
    }
  }
}

/// Coach-facing: approve/reject player parent requests.
struct CoachParentRequestsPanel: View {
  @EnvironmentObject private var appState: AppState

  @State private var requests: [SDParentInviteRequest] = []
  @State private var isLoading = false
  @State private var errorText: String?
  @State private var loadErrorText: String?

  @State private var noteByRequestId: [UUID: String] = [:]

  var body: some View {
    VStack(alignment: .leading, spacing: HP.Space.md) {
      HPSectionHeader("Pending requests") {
        HPButton(
          title: "Refresh",
          systemImage: "arrow.clockwise",
          variant: .secondary,
          size: .sm,
          action: { Task { await reload() } }
        )
        .disabled(isLoading)
      }

      if isLoading {
        HPLoadingState(text: "Loading parent requests…")
      } else if let loadErrorText {
        HPErrorState(
          title: "Parent requests unavailable",
          message: loadErrorText,
          onRetry: { Task { await reload() } }
        )
      } else if requests.isEmpty {
        HPEmptyState(
          title: "No pending requests",
          message: "New parent access requests will appear here for review.",
          systemImage: "person.badge.clock"
        )
      } else {
        ForEach(Array(requests.enumerated()), id: \.element.id) { index, request in
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            ViewThatFits(in: .horizontal) {
              HStack(alignment: .top, spacing: HP.Space.sm) {
                coachRequestDetails(request)
                Spacer(minLength: HP.Space.sm)
                HPStatusBadge(
                  text: request.status.capitalized,
                  kind: parentRequestStatusKind(request.status)
                )
              }
              VStack(alignment: .leading, spacing: HP.Space.xs) {
                coachRequestDetails(request)
                HPStatusBadge(
                  text: request.status.capitalized,
                  kind: parentRequestStatusKind(request.status)
                )
              }
            }

            HPFormField(
              label: "Coach note (optional)",
              text: Binding(
                get: { noteByRequestId[request.id] ?? "" },
                set: { noteByRequestId[request.id] = $0 }
              ),
              placeholder: "Add context for this decision",
              isEnabled: !isLoading
            )

            ViewThatFits(in: .horizontal) {
              HStack(spacing: HP.Space.sm) {
                reviewButtons(request, fullWidth: false)
                Spacer(minLength: 0)
              }
              VStack(alignment: .leading, spacing: HP.Space.sm) {
                reviewButtons(request, fullWidth: true)
              }
            }
          }
          .padding(.vertical, HP.Space.xs)
          if index < requests.count - 1 {
            Divider().overlay(HP.Color.border.opacity(0.5))
          }
        }
      }
    }
    .task { await reload() }
    .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { _ in errorText = nil })) {
      Button("OK", role: .cancel) {}
    } message: { Text(errorText ?? "") }
  }

  private func coachRequestDetails(_ request: SDParentInviteRequest) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(request.email_norm)
        .font(HP.Font.headline)
        .foregroundStyle(HP.Color.text)
        .fixedSize(horizontal: false, vertical: true)
      Text("Child: \(request.child_id.uuidString.prefix(6).uppercased())")
        .font(HP.Font.caption)
        .foregroundStyle(HP.Color.textMuted)
      if let relationship = request.relationship,
         !relationship.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        Text(relationship)
          .font(HP.Font.caption)
          .foregroundStyle(HP.Color.textMuted)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  @ViewBuilder
  private func reviewButtons(_ request: SDParentInviteRequest, fullWidth: Bool) -> some View {
    HPButton(
      title: "Approve",
      systemImage: "checkmark.circle",
      variant: .secondary,
      size: .md,
      fullWidth: fullWidth,
      action: { Task { await setStatus(request.id, status: "approved") } }
    )
    .disabled(isLoading)

    HPButton(
      title: "Reject",
      systemImage: "xmark.circle",
      variant: .destructive,
      size: .md,
      fullWidth: fullWidth,
      action: { Task { await setStatus(request.id, status: "rejected") } }
    )
    .disabled(isLoading)
  }

  private func reload() async {
    guard let supabase = appState.supabase else { return }
    loadErrorText = nil
    isLoading = true
    defer { isLoading = false }
    do {
      requests = try await supabase.coachListParentInviteRequests(status: "requested")
    } catch {
      loadErrorText = error.localizedDescription
      errorText = error.localizedDescription
    }
  }

  private func setStatus(_ requestId: UUID, status: String) async {
    guard let supabase = appState.supabase else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      try await supabase.coachUpdateParentInviteRequestStatus(
        requestId: requestId,
        status: status,
        coachNote: {
          let note = (noteByRequestId[requestId] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
          return note.isEmpty ? nil : note
        }()
      )
      noteByRequestId[requestId] = nil
      await reload()
    } catch {
      errorText = error.localizedDescription
    }
  }
}

private func parentRequestStatusKind(_ status: String) -> HPStatusKind {
  switch status.lowercased() {
  case "approved": .success
  case "rejected", "cancelled", "canceled": .danger
  case "requested", "pending": .warning
  default: .neutral
  }
}
