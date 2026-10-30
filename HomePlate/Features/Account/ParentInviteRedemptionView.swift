import SwiftUI

struct ParentInviteRedemptionView: View {
  @EnvironmentObject private var appState: AppState
  @Environment(\.dismiss) private var dismiss
  let redemption: SDParentInviteRedemption
  @State private var isAccepting = false
  @State private var errorText: String?

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: 18) {
        if let preview = appState.pendingParentInvitePreview {
          Label("Parent access invitation", systemImage: "person.2.fill")
            .font(.title2.bold())
          Text("\(preview.organization_name) invited you to connect with \(preview.child_name).")
          if let relationship = preview.relationship, !relationship.isEmpty {
            Text("Relationship: \(relationship)").foregroundStyle(.secondary)
          }
          Text("Sign in with the email address this invitation was sent to. Home Plate will verify the invitation and connect only the child named above.")
            .font(.footnote)
            .foregroundStyle(.secondary)
          Button {
            Task { await accept() }
          } label: {
            if isAccepting { ProgressView().frame(maxWidth: .infinity) }
            else { Text("Accept invitation").frame(maxWidth: .infinity) }
          }
          .buttonStyle(.borderedProminent)
          .disabled(isAccepting || !preview.valid)
        } else {
          ProgressView("Checking invitation…")
        }
        if let errorText {
          Text(errorText).font(.footnote).foregroundStyle(.red)
        }
        Spacer(minLength: 0)
      }
      .padding()
      .navigationTitle("Parent Invitation")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Close") { appState.dismissParentInviteRedemption(); dismiss() }
        }
      }
    }
    .task(id: redemption.id) {
      guard appState.pendingParentInvitePreview == nil,
            let service = appState.supabase else { return }
      do {
        appState.pendingParentInvitePreview = try await service.previewParentInvite(
          inviteId: redemption.inviteId, token: redemption.token
        )
      } catch {
        errorText = "This invitation has expired or is unavailable."
      }
    }
  }

  @MainActor
  private func accept() async {
    isAccepting = true
    defer { isAccepting = false }
    await appState.acceptPendingParentInvite()
    if appState.pendingParentInviteRedemption == nil { dismiss() }
  }
}
