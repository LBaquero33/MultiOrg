import SwiftUI

@MainActor
final class PlatformOrganizationCreationWorkflow: ObservableObject {
  @Published var isPresented = false
  @Published private(set) var isSubmitting = false
  @Published private(set) var errorText: String?
  @Published private(set) var successText: String?

  func present() {
    guard !isSubmitting else { return }
    errorText = nil
    successText = nil
    isPresented = true
  }

  func dismiss() {
    guard !isSubmitting else { return }
    isPresented = false
    errorText = nil
  }

  @discardableResult
  func submit(
    draft: PlatformOrganizationCreateDraft,
    create: (PlatformOrganizationCreateDraft) async throws -> SDPlatformOrganization,
    refresh: () async -> Void,
    errorMessage: (Error) -> String
  ) async -> SDPlatformOrganization? {
    guard !isSubmitting else { return nil }
    guard draft.isValid else {
      errorText = "Enter a name, a valid slug, and a positive optional member limit."
      return nil
    }

    isSubmitting = true
    errorText = nil
    defer { isSubmitting = false }
    do {
      let organization = try await create(draft)
      await refresh()
      successText = "\(organization.name) was created."
      isPresented = false
      return organization
    } catch {
      errorText = errorMessage(error)
      isPresented = true
      return nil
    }
  }
}

/// Platform-wide controls. This is intentionally separate from Org Admin:
/// it spans every organization and is only exposed after server authorization.
struct PlatformAdminDashboardView: View {
  @EnvironmentObject private var appState: AppState
  @State private var dashboard: SDPlatformDashboard?
  @State private var isLoading = false
  @State private var errorText: String?
  @State private var toastText: String?
  @State private var editingOrganization: PlatformOrganizationDraft?
  @StateObject private var creationWorkflow = PlatformOrganizationCreationWorkflow()

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        DHDHeaderCard {
          HStack {
            VStack(alignment: .leading, spacing: 4) {
              Text("Platform Admin")
                .font(.title2.weight(.bold))
              Text("Organizations, access, and billing health across MultiOrg.")
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.84))
            }
            Spacer()
            Button {
              creationWorkflow.present()
            } label: {
              Label("New Organization", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            Button { Task { await reload() } } label: {
              Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading)
          }
          .foregroundStyle(.white)
        }

        if isLoading && dashboard == nil {
          ProgressView("Loading platform health…")
            .frame(maxWidth: .infinity, minHeight: 180)
        } else if let dashboard {
          metricGrid(dashboard)
          ownerlessOrganizationWarning(dashboard.ownerless_organizations)
          unmanagedOrganizationWarning(dashboard.unmanaged_organizations)
          organizationCard(dashboard.organizations)
        } else {
          ContentUnavailableView("Platform data unavailable", systemImage: "building.2.crop.circle", description: Text("Refresh to load organization data."))
        }
      }
      .padding(DHDTheme.pagePadding)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .dhdPageBackground()
    .dhdToast($toastText)
    .navigationTitle("Platform Admin")
    .alert("Platform Admin", isPresented: Binding(get: { errorText != nil }, set: { _ in errorText = nil })) {
      Button("OK", role: .cancel) {}
    } message: { Text(errorText ?? "") }
    .sheet(item: $editingOrganization) { draft in
      PlatformOrganizationEditor(draft: draft) { updated in
        Task { await save(updated) }
      }
      #if os(macOS)
      .frame(minWidth: 520, minHeight: 430)
      #endif
    }
    .sheet(isPresented: $creationWorkflow.isPresented, onDismiss: {
      creationWorkflow.dismiss()
    }) {
      PlatformOrganizationCreateEditor(
        isSubmitting: creationWorkflow.isSubmitting,
        errorText: creationWorkflow.errorText
      ) { draft in
        Task { await create(draft) }
      }
      #if os(macOS)
      .frame(minWidth: 520, minHeight: 430)
      #endif
    }
    .task { await reload() }
  }

  @ViewBuilder
  private func ownerlessOrganizationWarning(_ organizations: [SDPlatformOrganization]) -> some View {
    if !organizations.isEmpty {
      DHDCard {
        VStack(alignment: .leading, spacing: 10) {
          Label("Owner assignment required", systemImage: "exclamationmark.shield.fill")
            .font(.headline)
            .foregroundStyle(.orange)
          Text("These organizations have no active owner. Active administrators do not satisfy the owner requirement; explicitly add an active owner before removing existing owner access.")
            .font(.footnote)
            .foregroundStyle(DHDTheme.textSecondary)
          ForEach(organizations) { organization in
            HStack {
              Text(organization.name)
                .font(.subheadline.weight(.semibold))
              Spacer()
              Text(organization.slug)
                .font(.caption.monospaced())
                .foregroundStyle(DHDTheme.textSecondary)
            }
          }
        }
      }
    }
  }

  @ViewBuilder
  private func unmanagedOrganizationWarning(_ organizations: [SDPlatformOrganization]) -> some View {
    if !organizations.isEmpty {
      DHDCard {
        VStack(alignment: .leading, spacing: 10) {
          Label("No active owner or administrator", systemImage: "person.crop.circle.badge.exclamationmark")
            .font(.headline)
            .foregroundStyle(.red)
          Text("These organizations have neither an active owner nor an active administrator. They are included in the owner-required diagnostic above and need deliberate platform review.")
            .font(.footnote)
            .foregroundStyle(DHDTheme.textSecondary)
          ForEach(organizations) { organization in
            HStack {
              Text(organization.name)
                .font(.subheadline.weight(.semibold))
              Spacer()
              Text(organization.slug)
                .font(.caption.monospaced())
                .foregroundStyle(DHDTheme.textSecondary)
            }
          }
        }
      }
    }
  }

  private func metricGrid(_ dashboard: SDPlatformDashboard) -> some View {
    let orgs = dashboard.organizations
    return LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
      metric("Organizations", orgs.count, "building.2.fill", .blue)
      metric("Active members", orgs.reduce(0) { $0 + $1.active_members }, "person.3.fill", .green)
      metric("Players", orgs.reduce(0) { $0 + $1.players }, "figure.baseball", .teal)
      metric("Active access", orgs.reduce(0) { $0 + $1.active_entitlements }, "creditcard.fill", .orange)
      metric("Teams", orgs.reduce(0) { $0 + $1.teams }, "person.3.sequence.fill", .purple)
    }
  }

  private func metric(_ title: String, _ value: Int, _ image: String, _ color: Color) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      Image(systemName: image).foregroundStyle(color)
      Text("\(value)").font(.title2.weight(.bold))
      Text(title).font(.caption).foregroundStyle(DHDTheme.textSecondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .background(DHDTheme.surfaceElevated.opacity(0.75))
    .clipShape(RoundedRectangle(cornerRadius: 8))
  }

  private func organizationCard(_ organizations: [SDPlatformOrganization]) -> some View {
    DHDCard {
      VStack(alignment: .leading, spacing: 12) {
        DHDSectionHeader("Organizations") { EmptyView() }
        if organizations.isEmpty {
          Text("No organizations yet.").foregroundStyle(DHDTheme.textSecondary)
        } else {
          ForEach(Array(organizations.enumerated()), id: \.element.id) { index, org in
            HStack(spacing: 12) {
              VStack(alignment: .leading, spacing: 3) {
                Text(org.name).font(.headline)
                Text("\(org.active_members) members • \(org.players) players • \(org.coaches) coaches")
                  .font(.caption).foregroundStyle(DHDTheme.textSecondary)
                Text("Plan: \(org.plan.capitalized) • Active access: \(org.active_entitlements)")
                  .font(.caption).foregroundStyle(DHDTheme.textSecondary)
              }
              Spacer()
              DHDStatusBadge(text: org.status.capitalized, color: org.status == "active" ? .green : .orange)
              NavigationLink {
                OrgAdminConsoleView(platformSupportOrganization: org)
                  .environmentObject(appState)
              } label: {
                Label("Support Payments", systemImage: "person.badge.shield.checkmark")
              }
              .buttonStyle(.bordered)
              .disabled(org.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "active")
              NavigationLink {
                FinanceDashboardView(
                  organizationId: org.id,
                  organizationName: org.name,
                  platformSupportMode: true
                )
                .environmentObject(appState)
              } label: {
                Label("Support Finance", systemImage: "chart.bar.xaxis")
              }
              .buttonStyle(.bordered)
              NavigationLink {
                NotificationCenterScreen(
                  announcementContext: NotificationAnnouncementContext(
                    organizationId: org.id,
                    organizationName: org.name,
                    supportMode: true,
                    canCreate: true
                  )
                )
                .environmentObject(appState)
              } label: {
                Label("Support Announce", systemImage: "megaphone.fill")
              }
              .buttonStyle(.bordered)
              .disabled(org.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "active")
              Button("Edit") { editingOrganization = PlatformOrganizationDraft(org) }
            }
            if index < organizations.count - 1 { Divider().overlay(DHDTheme.separator.opacity(0.3)) }
          }
        }
      }
    }
  }

  private func reload() async {
    guard let supabase = appState.supabase else { return }
    isLoading = true
    defer { isLoading = false }
    do { dashboard = try await supabase.platformAdminDashboard() }
    catch { errorText = "Platform data could not be loaded." }
  }

  private func save(_ draft: PlatformOrganizationDraft) async {
    guard let supabase = appState.supabase else { return }
    do {
      try await supabase.platformUpdateOrganization(draft.organization)
      editingOrganization = nil
      await reload()
    } catch {
      errorText = "Organization changes could not be saved."
    }
  }

  private func create(_ draft: PlatformOrganizationCreateDraft) async {
    let created = await creationWorkflow.submit(
      draft: draft,
      create: { draft in
        guard let supabase = appState.supabase else {
          throw NSError(
            domain: "PlatformAdmin",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Platform service is unavailable."]
          )
        }
        return try await supabase.platformCreateOrganization(
          name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
          slug: draft.normalizedSlug,
          plan: draft.plan,
          billingEmail: draft.cleanedBillingEmail,
          maxMembers: Int(draft.maxMembers)
        )
      },
      refresh: {
        await appState.refreshOrgContext()
        await reload()
      },
      errorMessage: { error in
        platformAdminMessage(for: error, fallback: "The organization could not be created. \(error.localizedDescription)")
      }
    )
    if created != nil {
      toastText = creationWorkflow.successText
    }
  }

  private func platformAdminMessage(for error: Error, fallback: String) -> String {
    let raw = error.localizedDescription
    if raw.localizedCaseInsensitiveContains("organization_slug_exists") {
      return "That organization slug is already in use. Choose another slug."
    }
    if raw.localizedCaseInsensitiveContains("invalid_organization_slug") {
      return "Use only lowercase letters, numbers, and hyphens in the organization slug."
    }
    return fallback
  }
}

struct PlatformOrganizationCreateDraft: Equatable {
  var name = ""
  var slug = ""
  var plan = "starter"
  var billingEmail = ""
  var maxMembers = ""

  var normalizedSlug: String {
    slug.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }

  var cleanedBillingEmail: String? {
    let value = billingEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return value.isEmpty ? nil : value
  }

  var isValid: Bool {
    !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && normalizedSlug.range(of: "^[a-z0-9][a-z0-9-]{1,62}$", options: .regularExpression) != nil
      && (maxMembers.isEmpty || (Int(maxMembers) ?? 0) > 0)
  }
}

struct PlatformOrganizationDraft: Identifiable {
  let original: SDPlatformOrganization
  var name: String
  var slug: String
  var status: String
  var plan: String
  var billingEmail: String
  var maxMembers: String
  var id: UUID { original.id }

  init(_ organization: SDPlatformOrganization) {
    original = organization
    name = organization.name
    slug = organization.slug
    status = organization.status
    plan = organization.plan
    billingEmail = organization.billing_email ?? ""
    maxMembers = organization.max_members.map(String.init) ?? ""
  }

  var organization: SDPlatformOrganization {
    SDPlatformOrganization(id: original.id, slug: slug, name: name, status: status, plan: plan,
      billing_email: billingEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : billingEmail,
      max_members: Int(maxMembers), active_members: original.active_members, players: original.players,
      coaches: original.coaches, active_entitlements: original.active_entitlements, teams: original.teams)
  }
}

private struct PlatformOrganizationCreateEditor: View {
  @Environment(\.dismiss) private var dismiss
  @State private var draft = PlatformOrganizationCreateDraft()
  @State private var didEditSlug = false
  @State private var generatedSlug = ""
  let isSubmitting: Bool
  let errorText: String?
  let onCreate: (PlatformOrganizationCreateDraft) -> Void

  var body: some View {
    NavigationStack {
      Form {
        Section("Organization") {
          TextField("Name", text: $draft.name)
            .onChange(of: draft.name) { _, newName in
              guard !didEditSlug || draft.slug == generatedSlug else { return }
              let nextSlug = slugify(newName)
              generatedSlug = nextSlug
              draft.slug = nextSlug
            }
          TextField("Slug", text: $draft.slug)
            .onChange(of: draft.slug) { _, value in
              if value != generatedSlug { didEditSlug = true }
            }
          Text("The slug identifies this organization at sign-in. Use lowercase letters, numbers, and hyphens.")
            .font(.footnote)
            .foregroundStyle(DHDTheme.textSecondary)
          TextField("Billing email (optional)", text: $draft.billingEmail)
          TextField("Member limit (optional)", text: $draft.maxMembers)
        }
        Section("Plan") {
          Picker("Plan", selection: $draft.plan) {
            Text("Starter").tag("starter")
            Text("Professional").tag("professional")
            Text("Enterprise").tag("enterprise")
          }
          Text("Temporary manual provisioning: you will become this organization’s initial owner. Add another owner before removing your access.")
            .font(.footnote)
            .foregroundStyle(DHDTheme.textSecondary)
          if let errorText {
            Text(errorText)
              .font(.footnote)
              .foregroundStyle(.red)
          }
          if isSubmitting {
            HStack(spacing: 8) {
              ProgressView()
              Text("Creating organization…")
            }
          }
        }
      }
      .navigationTitle("New Organization")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
            .disabled(isSubmitting)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(isSubmitting ? "Creating…" : "Create") { onCreate(draft) }
            .disabled(!draft.isValid || isSubmitting)
        }
      }
    }
  }

  private func slugify(_ input: String) -> String {
    input
      .lowercased()
      .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
      .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
  }
}

private struct PlatformOrganizationEditor: View {
  @Environment(\.dismiss) private var dismiss
  @State var draft: PlatformOrganizationDraft
  let onSave: (PlatformOrganizationDraft) -> Void

  init(draft: PlatformOrganizationDraft, onSave: @escaping (PlatformOrganizationDraft) -> Void) {
    _draft = State(initialValue: draft)
    self.onSave = onSave
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Organization") {
          TextField("Name", text: $draft.name)
          TextField("Slug", text: $draft.slug)
          TextField("Billing email", text: $draft.billingEmail)
          TextField("Member limit", text: $draft.maxMembers)
        }
        Section("Plan & Status") {
          Picker("Plan", selection: $draft.plan) {
            Text("Starter").tag("starter")
            Text("Professional").tag("professional")
            Text("Enterprise").tag("enterprise")
          }
          Picker("Status", selection: $draft.status) {
            Text("Active").tag("active")
            Text("Suspended").tag("suspended")
            Text("Archived").tag("archived")
          }
        }
      }
      .navigationTitle("Edit Organization")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            // Close immediately so a failed refresh cannot trap the admin in
            // this editor. The parent surface reports any save error clearly.
            dismiss()
            onSave(draft)
          }
        }
      }
    }
  }
}
