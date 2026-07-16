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
  @State private var organizationSearch = ""
  @State private var selectedOrganizationId: UUID?
  @State private var members: [SDPlatformMember] = []
  @State private var memberSearch = ""
  @State private var memberFilter: SDPlatformMemberFilter = .all
  @State private var isLoadingMembers = false
  @State private var editingMember: PlatformMembershipEditDraft?
  @State private var userSearch = ""
  @State private var userResults: [SDPlatformUserDirectoryEntry] = []
  @State private var isSearchingUsers = false
  @State private var platformAdministrators: [SDPlatformAdministrator] = []
  @State private var auditEntries: [SDPlatformAuditEntry] = []
  @State private var pendingPlatformAdminChange: PlatformAdministratorChange?
  @StateObject private var creationWorkflow = PlatformOrganizationCreationWorkflow()

  var body: some View {
    Group {
      if appState.isPlatformAdmin {
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
              organizationDirectory(dashboard.organizations)
              if let organization = dashboard.organizations.first(where: { $0.id == selectedOrganizationId }) {
                organizationMemberCard(organization)
              }
              globalUserLookupCard()
              platformAdministratorsCard()
              auditHistoryCard()
            } else {
              ContentUnavailableView("Platform data unavailable", systemImage: "building.2.crop.circle", description: Text("Refresh to load organization data."))
            }
          }
          .padding(DHDTheme.pagePadding)
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .dhdPageBackground()
      } else {
        ContentUnavailableView(
          "Platform Administration forbidden",
          systemImage: "lock.shield",
          description: Text("This workspace requires a server-authorized Home Plate platform administrator entitlement.")
        )
        .dhdPageBackground()
      }
    }
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
    .sheet(item: $editingMember) { draft in
      PlatformMembershipEditor(draft: draft) { update in
        Task { await applyMembershipUpdate(update) }
      }
      #if os(macOS)
      .frame(minWidth: 520, minHeight: 470)
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
    .confirmationDialog(
      "Confirm Platform Administrator Change",
      isPresented: Binding(
        get: { pendingPlatformAdminChange != nil },
        set: { if !$0 { pendingPlatformAdminChange = nil } }
      ),
      titleVisibility: .visible
    ) {
      if let change = pendingPlatformAdminChange {
        Button(change.granted ? "Grant Platform Admin" : "Revoke Platform Admin", role: change.granted ? nil : .destructive) {
          Task { await applyPlatformAdministratorChange(change) }
        }
      }
      Button("Cancel", role: .cancel) { pendingPlatformAdminChange = nil }
    } message: {
      Text("This is a platform-wide permission change. It will be authenticated and audited by the backend.")
    }
    .task {
      guard appState.isPlatformAdmin else { return }
      await reload()
    }
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

  private func organizationDirectory(_ organizations: [SDPlatformOrganization]) -> some View {
    let filtered = SDPlatformDirectory.organizations(organizations, matching: organizationSearch)
    return DHDCard {
      VStack(alignment: .leading, spacing: 12) {
        DHDSectionHeader("Organizations") { EmptyView() }
        TextField("Search organizations…", text: $organizationSearch)
          .textFieldStyle(.roundedBorder)
        if filtered.isEmpty {
          Text("No organizations match this search.")
            .foregroundStyle(DHDTheme.textSecondary)
        } else {
          ForEach(Array(filtered.enumerated()), id: \.element.id) { index, organization in
            Button {
              selectedOrganizationId = organization.id
              Task { await loadMembers(for: organization.id) }
            } label: {
              HStack(alignment: .top, spacing: 12) {
                Image(systemName: selectedOrganizationId == organization.id ? "checkmark.circle.fill" : "building.2")
                  .foregroundStyle(selectedOrganizationId == organization.id ? .blue : DHDTheme.textSecondary)
                VStack(alignment: .leading, spacing: 3) {
                  Text(organization.name).font(.headline)
                  Text(organization.id.uuidString.lowercased())
                    .font(.caption2.monospaced())
                    .foregroundStyle(DHDTheme.textSecondary)
                  Text("\(organization.active_members) members • \(organization.players) players • \(organization.coaches) staff")
                    .font(.caption)
                    .foregroundStyle(DHDTheme.textSecondary)
                }
                Spacer()
                DHDStatusBadge(
                  text: organization.status.capitalized,
                  color: organization.status == "active" ? .green : .orange
                )
              }
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if index < filtered.count - 1 {
              Divider().overlay(DHDTheme.separator.opacity(0.3))
            }
          }
        }
      }
    }
  }

  private func organizationMemberCard(_ organization: SDPlatformOrganization) -> some View {
    let filtered = SDPlatformDirectory.members(
      members,
      matching: memberSearch,
      filter: memberFilter
    )
    return DHDCard {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          VStack(alignment: .leading, spacing: 3) {
            Text("Organization Details").font(.headline)
            Text("\(organization.name) • \(organization.slug)")
              .font(.caption)
              .foregroundStyle(DHDTheme.textSecondary)
          }
          Spacer()
          Button("Edit Organization") { editingOrganization = PlatformOrganizationDraft(organization) }
          Button { Task { await loadMembers(for: organization.id) } } label: {
            Label("Refresh Members", systemImage: "arrow.clockwise")
          }
          .disabled(isLoadingMembers)
        }

        HStack {
          TextField("Search members by name, username, or email…", text: $memberSearch)
            .textFieldStyle(.roundedBorder)
          Picker("Role", selection: $memberFilter) {
            ForEach(SDPlatformMemberFilter.allCases) { filter in
              Text(filter.title).tag(filter)
            }
          }
          .frame(maxWidth: 190)
        }

        if isLoadingMembers {
          ProgressView("Loading members…")
            .frame(maxWidth: .infinity, minHeight: 100)
        } else if filtered.isEmpty {
          Text("No members match this search and filter.")
            .foregroundStyle(DHDTheme.textSecondary)
        } else {
          ForEach(Array(filtered.enumerated()), id: \.element.id) { index, member in
            HStack(alignment: .top, spacing: 12) {
              VStack(alignment: .leading, spacing: 3) {
                Text(member.displayName).font(.headline)
                if let username = member.username {
                  Text("@\(username)").font(.caption).foregroundStyle(DHDTheme.textSecondary)
                }
                if let email = member.email {
                  Text(email).font(.caption).foregroundStyle(DHDTheme.textSecondary)
                }
                HStack(spacing: 5) {
                  ForEach(member.badges, id: \.self) { badge in
                    DHDStatusBadge(text: badge, color: badge == "Player" ? .teal : .blue)
                  }
                }
                Text("Created: \(platformDate(member.created_at)) • Last activity: \(platformDate(member.last_activity))")
                  .font(.caption2)
                  .foregroundStyle(DHDTheme.textSecondary)
              }
              Spacer()
              VStack(alignment: .trailing, spacing: 8) {
                DHDStatusBadge(
                  text: member.status.capitalized,
                  color: member.isActive ? .green : .orange
                )
                Button("Edit Permissions") {
                  editingMember = PlatformMembershipEditDraft(member: member)
                }
              }
            }
            if index < filtered.count - 1 {
              Divider().overlay(DHDTheme.separator.opacity(0.3))
            }
          }
        }

        Text("Ownership transfer is a protected two-step operation: first promote the replacement owner, then demote or deactivate the previous owner. The final active owner cannot be removed.")
          .font(.caption)
          .foregroundStyle(DHDTheme.textSecondary)
      }
    }
  }

  private func globalUserLookupCard() -> some View {
    DHDCard {
      VStack(alignment: .leading, spacing: 12) {
        DHDSectionHeader("Global User Lookup") { EmptyView() }
        HStack {
          TextField("Search name, username, email, or user ID…", text: $userSearch)
            .textFieldStyle(.roundedBorder)
            .onSubmit { Task { await searchUsers() } }
          Button("Search") { Task { await searchUsers() } }
            .disabled(userSearch.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 || isSearchingUsers)
        }
        if isSearchingUsers { ProgressView() }
        ForEach(userResults) { user in
          HStack {
            VStack(alignment: .leading, spacing: 2) {
              Text(user.displayName).font(.subheadline.weight(.semibold))
              Text(user.email ?? user.user_id.uuidString.lowercased())
                .font(.caption)
                .foregroundStyle(DHDTheme.textSecondary)
              if !user.usernames.isEmpty {
                Text(user.usernames.map { "@\($0.username)" }.joined(separator: ", "))
                  .font(.caption2)
                  .foregroundStyle(DHDTheme.textSecondary)
              }
            }
            Spacer()
            Button("Grant Platform Admin") {
              pendingPlatformAdminChange = PlatformAdministratorChange(
                userId: user.user_id,
                granted: true
              )
            }
            .disabled(platformAdministrators.contains(where: { $0.user_id == user.user_id }))
          }
        }
      }
    }
  }

  private func platformAdministratorsCard() -> some View {
    DHDCard {
      VStack(alignment: .leading, spacing: 12) {
        DHDSectionHeader("Platform Administrators") { EmptyView() }
        if platformAdministrators.isEmpty {
          Text("No platform administrators were returned.")
            .foregroundStyle(DHDTheme.textSecondary)
        }
        ForEach(platformAdministrators) { administrator in
          HStack {
            VStack(alignment: .leading, spacing: 2) {
              Text(administrator.displayName).font(.subheadline.weight(.semibold))
              Text("Granted: \(platformDate(administrator.granted_at))")
                .font(.caption)
                .foregroundStyle(DHDTheme.textSecondary)
            }
            Spacer()
            Button("Revoke", role: .destructive) {
              pendingPlatformAdminChange = PlatformAdministratorChange(
                userId: administrator.user_id,
                granted: false
              )
            }
            .disabled(administrator.user_id == appState.myProfile?.id)
          }
        }
      }
    }
  }

  private func auditHistoryCard() -> some View {
    DHDCard {
      VStack(alignment: .leading, spacing: 12) {
        DHDSectionHeader("Recent Permission Changes") { EmptyView() }
        if auditEntries.isEmpty {
          Text("No recent permission changes.")
            .foregroundStyle(DHDTheme.textSecondary)
        }
        ForEach(auditEntries.prefix(25)) { entry in
          HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
              Text(entry.action.replacingOccurrences(of: "_", with: " ").capitalized)
                .font(.subheadline.weight(.semibold))
              Text(auditSummary(entry))
                .font(.caption)
                .foregroundStyle(DHDTheme.textSecondary)
            }
            Spacer()
            Text(platformDate(entry.created_at))
              .font(.caption2)
              .foregroundStyle(DHDTheme.textSecondary)
          }
        }
      }
    }
  }

  private func loadMembers(for organizationId: UUID) async {
    guard let supabase = appState.supabase,
          selectedOrganizationId == organizationId else { return }
    isLoadingMembers = true
    defer { isLoadingMembers = false }
    do {
      let response = try await supabase.platformOrganizationMembers(orgId: organizationId)
      guard selectedOrganizationId == response.organization.id else { return }
      members = response.members
    } catch {
      guard selectedOrganizationId == organizationId else { return }
      members = []
      errorText = "Organization members could not be loaded."
    }
  }

  private func searchUsers() async {
    guard let supabase = appState.supabase else { return }
    let query = userSearch.trimmingCharacters(in: .whitespacesAndNewlines)
    guard query.count >= 2 else { return }
    isSearchingUsers = true
    defer { isSearchingUsers = false }
    do {
      userResults = try await supabase.platformSearchUsers(query: query)
    } catch {
      userResults = []
      errorText = "Global users could not be searched."
    }
  }

  private func applyMembershipUpdate(_ update: PlatformMembershipEditDraft) async {
    guard let supabase = appState.supabase else { return }
    do {
      _ = try await supabase.platformUpdateMembership(
        orgId: update.member.org_id,
        userId: update.member.user_id,
        role: update.role,
        status: update.status,
        reason: update.cleanedReason,
        requestId: update.requestId
      )
      editingMember = nil
      toastText = "Permissions updated for \(update.member.displayName)."
      await loadMembers(for: update.member.org_id)
      await reloadPlatformSupportingData()
      await appState.refreshOrgContext()
    } catch {
      let raw = error.localizedDescription.lowercased()
      errorText = raw.contains("last_active_owner_required")
        ? "Promote another active owner before removing, demoting, or deactivating the final owner."
        : "The permission change could not be applied."
    }
  }

  private func applyPlatformAdministratorChange(_ change: PlatformAdministratorChange) async {
    guard let supabase = appState.supabase else { return }
    pendingPlatformAdminChange = nil
    do {
      try await supabase.platformSetAdministrator(
        userId: change.userId,
        granted: change.granted,
        reason: nil,
        requestId: change.requestId
      )
      toastText = change.granted
        ? "Platform administrator access granted."
        : "Platform administrator access revoked."
      await reloadPlatformSupportingData()
    } catch {
      errorText = "The platform administrator change could not be applied."
    }
  }

  private func reloadPlatformSupportingData() async {
    guard let supabase = appState.supabase else { return }
    async let loadedAdministrators = try? supabase.platformAdministrators()
    async let loadedAudit = try? supabase.platformAuditHistory()
    platformAdministrators = await loadedAdministrators ?? []
    auditEntries = await loadedAudit ?? []
  }

  private func platformDate(_ value: String?) -> String {
    guard let value, !value.isEmpty else { return "Not available" }
    return String(value.prefix(10))
  }

  private func auditSummary(_ entry: SDPlatformAuditEntry) -> String {
    let previousRole = entry.details["previous_role"]?.stringValue
    let newRole = entry.details["new_role"]?.stringValue
    let previousStatus = entry.details["previous_status"]?.stringValue
    let newStatus = entry.details["new_status"]?.stringValue
    let roleChange = [previousRole, newRole].compactMap { $0 }.joined(separator: " → ")
    let statusChange = [previousStatus, newStatus].compactMap { $0 }.joined(separator: " → ")
    let changes = [roleChange, statusChange].filter { !$0.isEmpty }.joined(separator: " • ")
    return changes.isEmpty ? (entry.target_id ?? entry.target_type) : changes
  }

  private func reload() async {
    guard let supabase = appState.supabase else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      dashboard = try await supabase.platformAdminDashboard()
      await reloadPlatformSupportingData()
      if let selectedOrganizationId {
        await loadMembers(for: selectedOrganizationId)
      }
    }
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

struct PlatformMembershipEditDraft: Identifiable, Equatable {
  let member: SDPlatformMember
  var role: String
  var status: String
  var reason = ""
  let requestId: UUID
  var id: String { member.id }

  init(member: SDPlatformMember, requestId: UUID = UUID()) {
    self.member = member
    role = member.normalizedRole
    status = member.normalizedStatus
    self.requestId = requestId
  }

  var cleanedReason: String? {
    let value = reason.trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : value
  }

  var hasChanges: Bool {
    role != member.normalizedRole || status != member.normalizedStatus
  }
}

struct PlatformAdministratorChange: Identifiable, Equatable {
  let userId: UUID
  let granted: Bool
  let requestId: UUID
  var id: UUID { requestId }

  init(userId: UUID, granted: Bool, requestId: UUID = UUID()) {
    self.userId = userId
    self.granted = granted
    self.requestId = requestId
  }
}

private struct PlatformMembershipEditor: View {
  @Environment(\.dismiss) private var dismiss
  @State var draft: PlatformMembershipEditDraft
  @State private var isConfirming = false
  let onApply: (PlatformMembershipEditDraft) -> Void

  init(
    draft: PlatformMembershipEditDraft,
    onApply: @escaping (PlatformMembershipEditDraft) -> Void
  ) {
    _draft = State(initialValue: draft)
    self.onApply = onApply
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Member") {
          Text(draft.member.displayName)
          if let email = draft.member.email { Text(email).foregroundStyle(.secondary) }
          Text(draft.member.user_id.uuidString.lowercased())
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
        }
        Section("Organization Permissions") {
          Picker("Role", selection: $draft.role) {
            ForEach(["owner", "admin", "coach", "player", "parent"], id: \.self) {
              Text($0.capitalized).tag($0)
            }
          }
          Picker("Status", selection: $draft.status) {
            ForEach(["active", "invited", "disabled", "suspended"], id: \.self) {
              Text($0.capitalized).tag($0)
            }
          }
          TextField("Reason (optional)", text: $draft.reason, axis: .vertical)
          if draft.member.normalizedRole == "owner"
            && (draft.role != "owner" || draft.status != "active") {
            Label(
              "Another active owner must exist before this change can succeed.",
              systemImage: "exclamationmark.shield.fill"
            )
            .foregroundStyle(.orange)
          }
          Text("Organization permissions come from this membership only. Platform administrator access is managed separately.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }
      .navigationTitle("Permission Editor")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Review Change") { isConfirming = true }
            .disabled(!draft.hasChanges || draft.reason.count > 500)
        }
      }
      .confirmationDialog(
        "Apply Organization Permission Change?",
        isPresented: $isConfirming,
        titleVisibility: .visible
      ) {
        Button("Apply Change") { onApply(draft) }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("Change \(draft.member.displayName) from \(draft.member.role)/\(draft.member.status) to \(draft.role)/\(draft.status). This request will be authorized, idempotent, and audited by the backend.")
      }
    }
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
