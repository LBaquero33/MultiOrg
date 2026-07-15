import SwiftUI

/// Player-facing: request parent access (coach approves) + view linked parents.
struct PlayerParentRequestsPanel: View {
  @EnvironmentObject private var appState: AppState

  @State private var linkedParents: [(Profile, SDParentChildLink)] = []
  @State private var requests: [SDParentInviteRequest] = []
  @State private var isLoading = false
  @State private var errorText: String?

  @State private var parentEmail: String = ""
  @State private var relationship: String = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if isLoading {
        HStack(spacing: 10) { ProgressView(); Text("Loading…").foregroundStyle(DHDTheme.textSecondary) }
      }

      if linkedParents.isEmpty {
        Text("No parents linked yet.")
          .foregroundStyle(DHDTheme.textSecondary)
      } else {
        VStack(alignment: .leading, spacing: 8) {
          Text("Linked parents")
            .font(.subheadline.weight(.semibold))
          ForEach(linkedParents, id: \.0.id) { parent, link in
            HStack {
              Text(parent.displayName)
              Spacer()
              if let rel = link.relationship, !rel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                DHDStatusBadge(text: rel, color: .blue)
              }
            }
            .foregroundStyle(DHDTheme.textPrimary)
          }
        }
      }

      Divider().overlay(DHDTheme.separator.opacity(0.5))

      VStack(alignment: .leading, spacing: 8) {
        Text("Request parent access")
          .font(.subheadline.weight(.semibold))
        Text("Enter a parent/guardian email. A coach will approve it before the parent can link.")
          .font(.caption)
          .foregroundStyle(DHDTheme.textSecondary)

        TextField("Parent email", text: $parentEmail)
          .textFieldStyle(.roundedBorder)
#if canImport(UIKit)
          .textInputAutocapitalization(.never)
#endif
          .autocorrectionDisabled()

        TextField("Relationship (optional)", text: $relationship)
          .textFieldStyle(.roundedBorder)

        Button {
          Task { await submitRequest() }
        } label: {
          Label("Send request", systemImage: "paperplane")
        }
        .buttonStyle(.borderedProminent)
        .disabled(parentEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }

      Divider().overlay(DHDTheme.separator.opacity(0.5))

      VStack(alignment: .leading, spacing: 8) {
        Text("Requests")
          .font(.subheadline.weight(.semibold))
        if requests.isEmpty {
          Text("No requests yet.")
            .foregroundStyle(DHDTheme.textSecondary)
        } else {
          ForEach(requests) { r in
            HStack {
              VStack(alignment: .leading, spacing: 2) {
                Text(r.email_norm)
                Text(r.status.capitalized)
                  .font(.caption)
                  .foregroundStyle(DHDTheme.textSecondary)
                if let note = r.coach_note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                  Text(note)
                    .font(.caption)
                    .foregroundStyle(DHDTheme.textSecondary)
                }
              }
              Spacer()
              if r.status.lowercased() == "requested" {
                Button(role: .destructive) {
                  Task { await cancelRequest(id: r.id) }
                } label: {
                  Text("Cancel")
                }
                .buttonStyle(.bordered)
              }
            }
            .padding(.vertical, 2)
          }
        }
      }
    }
    .task { await reload() }
    .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { _ in errorText = nil })) {
      Button("OK", role: .cancel) {}
    } message: { Text(errorText ?? "") }
  }

  private func reload() async {
    guard let supabase = appState.supabase else { return }
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

  @State private var noteByRequestId: [UUID: String] = [:]

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("Pending requests")
          .font(.subheadline.weight(.semibold))
        Spacer()
        Button {
          Task { await reload() }
        } label: {
          Image(systemName: "arrow.clockwise")
        }
        .buttonStyle(.bordered)
      }

      if isLoading {
        HStack(spacing: 10) { ProgressView(); Text("Loading…").foregroundStyle(DHDTheme.textSecondary) }
      } else if requests.isEmpty {
        Text("No pending requests.")
          .foregroundStyle(DHDTheme.textSecondary)
      } else {
        ForEach(requests) { r in
          VStack(alignment: .leading, spacing: 8) {
            HStack {
              VStack(alignment: .leading, spacing: 2) {
                Text(r.email_norm).font(.headline)
                Text("Child: \(r.child_id.uuidString.prefix(6).uppercased())")
                  .font(.caption)
                  .foregroundStyle(DHDTheme.textSecondary)
                if let rel = r.relationship, !rel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                  Text(rel).font(.caption).foregroundStyle(DHDTheme.textSecondary)
                }
              }
              Spacer()
              DHDStatusBadge(text: r.status.capitalized, color: .blue)
            }

            TextField("Coach note (optional)", text: Binding(
              get: { noteByRequestId[r.id] ?? "" },
              set: { noteByRequestId[r.id] = $0 }
            ))
              .textFieldStyle(.roundedBorder)

            HStack(spacing: 10) {
              Button {
                Task { await setStatus(r.id, status: "approved") }
              } label: {
                Label("Approve", systemImage: "checkmark.circle")
              }
              .buttonStyle(.borderedProminent)

              Button(role: .destructive) {
                Task { await setStatus(r.id, status: "rejected") }
              } label: {
                Label("Reject", systemImage: "xmark.circle")
              }
              .buttonStyle(.bordered)

              Spacer()
            }
          }
          .padding(.vertical, 6)
          Divider().overlay(DHDTheme.separator.opacity(0.5))
        }
      }
    }
    .task { await reload() }
    .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { _ in errorText = nil })) {
      Button("OK", role: .cancel) {}
    } message: { Text(errorText ?? "") }
  }

  private func reload() async {
    guard let supabase = appState.supabase else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      requests = try await supabase.coachListParentInviteRequests(status: "requested")
    } catch {
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
