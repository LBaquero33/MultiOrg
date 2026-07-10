import SwiftUI

struct OrgAdminConsoleView: View {
  @EnvironmentObject private var appState: AppState

  @State private var settings: SDOrgSettings?
  @State private var facilities: [SDFacility] = []
  @State private var adminMembers: [SDOrgAdminMember] = []
  @State private var isLoading = false
  @State private var errorText: String?
  @State private var toastText: String?

  @State private var selectedTab: Tab = .branding
  @State private var editingFacility: FacilityDraft?
  @State private var isShowingCreateMember = false
  @State private var editingMember: MemberDraft?

  // Branding/settings
  @State private var displayName = ""
  @State private var shortName = ""
  @State private var supportEmail = ""
  @State private var websiteHost = ""
  @State private var primaryHex = "#0D2445"
  @State private var secondaryHex = "#0A3854"
  @State private var accentHex = "#4D9EF9"

  // Terminology
  @State private var playerSingular = "Player"
  @State private var playerPlural = "Players"
  @State private var coachSingular = "Coach"
  @State private var coachPlural = "Coaches"
  @State private var facilitySingular = "Facility"
  @State private var facilityPlural = "Facilities"
  @State private var programLabel = "Program"
  @State private var testingLabel = "Testing"

  // Features
  @State private var featureFacilities = true
  @State private var featureChat = true
  @State private var featurePrograms = true
  @State private var featureTesting = true
  @State private var featureBPAnalysis = true
  @State private var featureParentPortal = true
  @State private var featureBilling = true

  // Booking policy
  @State private var defaultDuration = "60"
  @State private var minDuration = "30"
  @State private var maxDuration = "120"
  @State private var allowPlayerRequests = true
  @State private var requireCoachApproval = true

  enum Tab: String, CaseIterable, Identifiable {
    case branding = "Branding"
    case terminology = "Terminology"
    case features = "Features"
    case facilities = "Facilities"
    case members = "Members"
    var id: String { rawValue }
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        header

        Picker("Admin section", selection: $selectedTab) {
          ForEach(Tab.allCases) { tab in
            Text(tab.rawValue).tag(tab)
          }
        }
        #if os(macOS)
        .pickerStyle(.segmented)
        #else
        .pickerStyle(.menu)
        #endif

        Group {
          switch selectedTab {
          case .branding:
            brandingCard
            bookingPolicyCard
          case .terminology:
            terminologyCard
          case .features:
            featureFlagsCard
          case .facilities:
            facilitiesCard
          case .members:
            membersCard
          }
        }
      }
      .padding(DHDTheme.pagePadding)
      .frame(maxWidth: .infinity, alignment: .leading)
      .frame(maxHeight: .infinity, alignment: .topLeading)
    }
    .background(DHDTheme.pageBackground)
    .navigationTitle("Org Admin")
    .dhdToast($toastText)
    .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { _ in errorText = nil })) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(errorText ?? "")
    }
    .sheet(item: $editingFacility) { draft in
      FacilityAdminEditorSheet(draft: draft) { saved in
        Task { await saveFacility(saved) }
      }
      .environmentObject(appState)
      #if os(macOS)
      .frame(minWidth: 560, minHeight: 560)
      #endif
    }
    .sheet(isPresented: $isShowingCreateMember) {
      CreateOrgMemberSheet { draft in
        Task { await createMember(draft) }
      }
      #if os(macOS)
      .frame(minWidth: 560, minHeight: 520)
      #endif
    }
    .sheet(item: $editingMember) { draft in
      EditOrgMemberSheet(draft: draft) { saved in
        Task { await updateMember(saved) }
      }
      #if os(macOS)
      .frame(minWidth: 520, minHeight: 420)
      #endif
    }
    .task { await reload() }
  }

  private var header: some View {
    DHDHeaderCard {
      HStack(alignment: .center, spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Organization Admin Console")
            .font(.title3.weight(.semibold))
          Text(activeOrgSubtitle)
            .font(.caption)
            .foregroundStyle(Color.white.opacity(0.84))
        }
        Spacer()
        if isLoading {
          ProgressView().tint(.white)
        }
        Button {
          Task { await saveSettings() }
        } label: {
          Label("Save", systemImage: "checkmark.circle.fill")
        }
        .buttonStyle(.borderedProminent)
        .disabled(isLoading || appState.activeOrgId == nil)
      }
      .foregroundStyle(.white)
    }
  }

  private var activeOrgSubtitle: String {
    if let s = settings {
      return s.display_name ?? s.short_name ?? "Customize this organization"
    }
    if appState.activeOrgId != nil {
      return "Customize this organization"
    }
    return "No active organization found for this account."
  }

  private var brandingCard: some View {
    DHDCard {
      VStack(alignment: .leading, spacing: 12) {
        DHDSectionHeader("Branding & Contact") {
          Button("Save") { Task { await saveSettings() } }
        }

        TextField("Display name", text: $displayName)
          .textFieldStyle(.roundedBorder)
        TextField("Short name", text: $shortName)
          .textFieldStyle(.roundedBorder)

        HStack(spacing: 10) {
          TextField("Support email", text: $supportEmail)
            .textFieldStyle(.roundedBorder)
          TextField("Website host", text: $websiteHost)
            .textFieldStyle(.roundedBorder)
        }

        Text("Brand colors")
          .font(.headline)
          .padding(.top, 4)
        HStack(spacing: 10) {
          hexField("Primary", text: $primaryHex)
          hexField("Secondary", text: $secondaryHex)
          hexField("Accent", text: $accentHex)
        }
      }
    }
  }

  private var terminologyCard: some View {
    DHDCard {
      VStack(alignment: .leading, spacing: 12) {
        DHDSectionHeader("Terminology") {
          Button("Save") { Task { await saveSettings() } }
        }

        Text("Rename core concepts per organization. This lets one org call them players/cages while another uses athletes/lanes/resources.")
          .font(.footnote)
          .foregroundStyle(DHDTheme.textSecondary)

        HStack(spacing: 10) {
          TextField("Player singular", text: $playerSingular)
            .textFieldStyle(.roundedBorder)
          TextField("Player plural", text: $playerPlural)
            .textFieldStyle(.roundedBorder)
        }
        HStack(spacing: 10) {
          TextField("Coach singular", text: $coachSingular)
            .textFieldStyle(.roundedBorder)
          TextField("Coach plural", text: $coachPlural)
            .textFieldStyle(.roundedBorder)
        }
        HStack(spacing: 10) {
          TextField("Facility singular", text: $facilitySingular)
            .textFieldStyle(.roundedBorder)
          TextField("Facility plural", text: $facilityPlural)
            .textFieldStyle(.roundedBorder)
        }
        HStack(spacing: 10) {
          TextField("Program label", text: $programLabel)
            .textFieldStyle(.roundedBorder)
          TextField("Testing label", text: $testingLabel)
            .textFieldStyle(.roundedBorder)
        }
      }
    }
  }

  private var featureFlagsCard: some View {
    DHDCard {
      VStack(alignment: .leading, spacing: 12) {
        DHDSectionHeader("Feature Flags") {
          Button("Save") { Task { await saveSettings() } }
        }

        Toggle("Facilities / booking", isOn: $featureFacilities)
        Toggle("Chat", isOn: $featureChat)
        Toggle("Programs", isOn: $featurePrograms)
        Toggle("Testing", isOn: $featureTesting)
        Toggle("BP analysis", isOn: $featureBPAnalysis)
        Toggle("Parent portal", isOn: $featureParentPortal)
        Toggle("Billing/payment requests", isOn: $featureBilling)
      }
    }
  }

  private var bookingPolicyCard: some View {
    DHDCard {
      VStack(alignment: .leading, spacing: 12) {
        DHDSectionHeader("Booking Policy") {
          Button("Save") { Task { await saveSettings() } }
        }

        HStack(spacing: 10) {
          TextField("Default duration", text: $defaultDuration)
            .textFieldStyle(.roundedBorder)
          TextField("Minimum duration", text: $minDuration)
            .textFieldStyle(.roundedBorder)
          TextField("Maximum duration", text: $maxDuration)
            .textFieldStyle(.roundedBorder)
        }
        Toggle("Players can request bookings", isOn: $allowPlayerRequests)
        Toggle("Bookings require coach approval", isOn: $requireCoachApproval)
      }
    }
  }

  private var facilitiesCard: some View {
    DHDCard {
      VStack(alignment: .leading, spacing: 12) {
        DHDSectionHeader("Facility Resources") {
          Button {
            editingFacility = FacilityDraft.new(orgId: appState.activeOrgId)
          } label: {
            Label("Add", systemImage: "plus")
          }
        }

        if facilities.isEmpty {
          Text("No facilities configured yet.")
            .foregroundStyle(DHDTheme.textSecondary)
        } else {
          ForEach(facilities) { facility in
            HStack(spacing: 12) {
              Circle()
                .fill(colorFromHex(facility.color_hex) ?? DHDTheme.accent)
                .frame(width: 12, height: 12)
              VStack(alignment: .leading, spacing: 2) {
                Text(facility.name)
                  .font(.headline)
                Text("\(facility.resource_type ?? "resource") • capacity \(facility.capacity ?? 1) • sort \(facility.sort_order)")
                  .font(.caption)
                  .foregroundStyle(DHDTheme.textSecondary)
              }
              Spacer()
              DHDStatusBadge(text: facility.is_active ? "Active" : "Hidden", color: facility.is_active ? .green : .orange)
              Button("Edit") {
                editingFacility = FacilityDraft(facility: facility, orgId: appState.activeOrgId)
              }
            }
            Divider().overlay(DHDTheme.separator.opacity(0.25))
          }
        }
      }
    }
  }

  private var membersCard: some View {
    DHDCard {
      VStack(alignment: .leading, spacing: 12) {
        DHDSectionHeader("Users & Org Access") {
          HStack {
            Button("Refresh") { Task { await reload() } }
            Button {
              isShowingCreateMember = true
            } label: {
              Label("Create User", systemImage: "person.badge.plus")
            }
          }
        }

        Text("Create organization-specific accounts, assign roles, disable access, and update the username used by the org login screen.")
          .font(.footnote)
          .foregroundStyle(DHDTheme.textSecondary)

        if adminMembers.isEmpty {
          Text("No memberships visible.")
            .foregroundStyle(DHDTheme.textSecondary)
        } else {
          ForEach(adminMembers) { member in
            HStack(spacing: 12) {
              VStack(alignment: .leading, spacing: 2) {
                Text(member.displayName)
                  .font(.headline)
                Text(member.email ?? member.user_id.uuidString)
                  .font(.caption)
                  .foregroundStyle(DHDTheme.textSecondary)
                if let username = member.username {
                  Text("@\(username)")
                    .font(.caption)
                    .foregroundStyle(DHDTheme.textSecondary)
                }
              }
              Spacer()
              DHDStatusBadge(text: member.status.capitalized, color: member.status == "active" ? .green : .orange)
              DHDStatusBadge(text: member.role.capitalized, color: member.isAdmin ? .green : DHDTheme.accent)
              Button("Edit") {
                editingMember = MemberDraft(member: member)
              }
            }
            Divider().overlay(DHDTheme.separator.opacity(0.25))
          }
        }
      }
    }
  }

  private func hexField(_ label: String, text: Binding<String>) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(label)
        .font(.caption)
        .foregroundStyle(DHDTheme.textSecondary)
      HStack {
        RoundedRectangle(cornerRadius: 6)
          .fill(colorFromHex(text.wrappedValue) ?? .clear)
          .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(DHDTheme.separator, lineWidth: 1))
          .frame(width: 26, height: 26)
        TextField("#RRGGBB", text: text)
          .textFieldStyle(.roundedBorder)
      }
    }
  }

  private func reload() async {
    guard let supabase = appState.supabase else { return }
    guard let orgId = appState.activeOrgId else {
      errorText = "No active organization found."
      return
    }
    isLoading = true
    defer { isLoading = false }
    do {
      let loadedSettings = try await supabase.fetchOrgSettings(orgId: orgId)
      settings = loadedSettings
      facilities = try await supabase.listFacilities(orgId: orgId, includeInactive: true)
      adminMembers = try await supabase.adminListOrgMembers(orgId: orgId)

      applySettingsToFields(loadedSettings)
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func applySettingsToFields(_ settings: SDOrgSettings?) {
    displayName = settings?.display_name ?? ""
    shortName = settings?.short_name ?? ""
    supportEmail = settings?.support_email ?? ""
    websiteHost = settings?.website_host ?? ""
    primaryHex = settings?.primary_color_hex ?? "#0D2445"
    secondaryHex = settings?.secondary_color_hex ?? "#0A3854"
    accentHex = settings?.accent_color_hex ?? "#4D9EF9"

    playerSingular = settings?.term("player", fallback: "Player") ?? "Player"
    playerPlural = settings?.term("players", fallback: "Players") ?? "Players"
    coachSingular = settings?.term("coach", fallback: "Coach") ?? "Coach"
    coachPlural = settings?.term("coaches", fallback: "Coaches") ?? "Coaches"
    facilitySingular = settings?.term("facility", fallback: "Facility") ?? "Facility"
    facilityPlural = settings?.term("facilities", fallback: "Facilities") ?? "Facilities"
    programLabel = settings?.term("program", fallback: "Program") ?? "Program"
    testingLabel = settings?.term("testing", fallback: "Testing") ?? "Testing"

    featureFacilities = settings?.feature("facilities") ?? true
    featureChat = settings?.feature("chat") ?? true
    featurePrograms = settings?.feature("programs") ?? true
    featureTesting = settings?.feature("testing") ?? true
    featureBPAnalysis = settings?.feature("bpAnalysis") ?? true
    featureParentPortal = settings?.feature("parentPortal") ?? true
    featureBilling = settings?.feature("billing") ?? true

    defaultDuration = String(settings?.bookingInt("defaultDurationMinutes", default: 60) ?? 60)
    minDuration = String(settings?.bookingInt("minDurationMinutes", default: 30) ?? 30)
    maxDuration = String(settings?.bookingInt("maxDurationMinutes", default: 120) ?? 120)
    allowPlayerRequests = settings?.booking_policy["allowPlayerRequests"]?.boolValue ?? true
    requireCoachApproval = settings?.booking_policy["requireCoachApproval"]?.boolValue ?? true
  }

  private func saveSettings() async {
    guard let supabase = appState.supabase else { return }
    guard let orgId = appState.activeOrgId else {
      errorText = "No active organization found."
      return
    }
    isLoading = true
    defer { isLoading = false }
    do {
      let payload = SupabaseService.SDOrgSettingsUpsert(
        org_id: orgId,
        display_name: clean(displayName),
        short_name: clean(shortName),
        support_email: clean(supportEmail),
        website_host: clean(websiteHost),
        primary_color_hex: normalizeHex(primaryHex, fallback: "#0D2445"),
        secondary_color_hex: normalizeHex(secondaryHex, fallback: "#0A3854"),
        accent_color_hex: normalizeHex(accentHex, fallback: "#4D9EF9"),
        terminology: [
          "player": .string(nonEmpty(playerSingular, fallback: "Player")),
          "players": .string(nonEmpty(playerPlural, fallback: "Players")),
          "coach": .string(nonEmpty(coachSingular, fallback: "Coach")),
          "coaches": .string(nonEmpty(coachPlural, fallback: "Coaches")),
          "facility": .string(nonEmpty(facilitySingular, fallback: "Facility")),
          "facilities": .string(nonEmpty(facilityPlural, fallback: "Facilities")),
          "program": .string(nonEmpty(programLabel, fallback: "Program")),
          "testing": .string(nonEmpty(testingLabel, fallback: "Testing")),
        ],
        feature_flags: [
          "facilities": .bool(featureFacilities),
          "chat": .bool(featureChat),
          "programs": .bool(featurePrograms),
          "testing": .bool(featureTesting),
          "bpAnalysis": .bool(featureBPAnalysis),
          "parentPortal": .bool(featureParentPortal),
          "billing": .bool(featureBilling),
        ],
        booking_policy: [
          "defaultDurationMinutes": .int(Int(defaultDuration) ?? 60),
          "minDurationMinutes": .int(Int(minDuration) ?? 30),
          "maxDurationMinutes": .int(Int(maxDuration) ?? 120),
          "allowPlayerRequests": .bool(allowPlayerRequests),
          "requireCoachApproval": .bool(requireCoachApproval),
        ],
        dashboard_layout: settings?.dashboard_layout ?? [
          "showOperations": .bool(true),
          "showRosterBadges": .bool(true),
          "showFacilitySnapshot": .bool(true),
        ]
      )
      settings = try await supabase.upsertOrgSettings(payload)
      await appState.refreshOrgContext()
      toastText = "Organization settings saved."
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func saveFacility(_ draft: FacilityDraft) async {
    guard let supabase = appState.supabase else { return }
    guard let orgId = appState.activeOrgId else {
      errorText = "No active organization found."
      return
    }
    isLoading = true
    defer { isLoading = false }
    do {
      let payload = SupabaseService.SDFacilityUpsert(
        id: draft.id,
        org_id: orgId,
        name: nonEmpty(draft.name, fallback: "Resource"),
        is_active: draft.isActive,
        sort_order: Int(draft.sortOrder) ?? 0,
        resource_type: nonEmpty(draft.resourceType, fallback: "cage").lowercased(),
        color_hex: clean(normalizeHex(draft.colorHex, fallback: "")),
        capacity: max(1, Int(draft.capacity) ?? 1),
        metadata: [
          "fullResourceGroup": .string(draft.fullResourceGroup.trimmingCharacters(in: .whitespacesAndNewlines)),
          "notes": .string(draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)),
        ]
      )
      if draft.id == nil {
        _ = try await supabase.createFacility(payload)
      } else {
        _ = try await supabase.updateFacility(payload)
      }
      editingFacility = nil
      toastText = "Facility saved."
      await reload()
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func createMember(_ draft: CreateMemberDraft) async {
    guard let supabase = appState.supabase else { return }
    guard let orgId = appState.activeOrgId else {
      errorText = "No active organization found."
      return
    }
    isLoading = true
    defer { isLoading = false }
    do {
      _ = try await supabase.adminCreateOrgUser(
        orgId: orgId,
        email: draft.email.trimmingCharacters(in: .whitespacesAndNewlines),
        username: draft.username.trimmingCharacters(in: .whitespacesAndNewlines),
        password: draft.password,
        fullName: clean(draft.fullName),
        role: draft.role
      )
      isShowingCreateMember = false
      toastText = "Org user created."
      await reload()
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func updateMember(_ draft: MemberDraft) async {
    guard let supabase = appState.supabase else { return }
    guard let orgId = appState.activeOrgId else {
      errorText = "No active organization found."
      return
    }
    isLoading = true
    defer { isLoading = false }
    do {
      try await supabase.adminUpdateOrgMember(
        orgId: orgId,
        userId: draft.userId,
        role: draft.role,
        status: draft.status
      )
      if !draft.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        try await supabase.adminSetOrgUsername(
          orgId: orgId,
          userId: draft.userId,
          username: draft.username.trimmingCharacters(in: .whitespacesAndNewlines)
        )
      }
      editingMember = nil
      toastText = "Member updated."
      await reload()
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func clean(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private func nonEmpty(_ value: String, fallback: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? fallback : trimmed
  }

  private func normalizeHex(_ value: String, fallback: String) -> String {
    let raw = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    let withHash = raw.hasPrefix("#") ? raw : "#\(raw)"
    guard withHash.count == 7 else { return fallback }
    let allowed = CharacterSet(charactersIn: "#0123456789ABCDEF")
    guard withHash.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return fallback }
    return withHash
  }

  private func colorFromHex(_ value: String?) -> Color? {
    guard let value else { return nil }
    let hex = normalizeHex(value, fallback: "")
    guard hex.count == 7 else { return nil }
    let scanner = Scanner(string: String(hex.dropFirst()))
    var rgb: UInt64 = 0
    guard scanner.scanHexInt64(&rgb) else { return nil }
    return Color(
      red: Double((rgb & 0xFF0000) >> 16) / 255,
      green: Double((rgb & 0x00FF00) >> 8) / 255,
      blue: Double(rgb & 0x0000FF) / 255
    )
  }
}

struct FacilityDraft: Identifiable, Equatable {
  var id: UUID?
  var orgId: UUID?
  var name: String
  var isActive: Bool
  var sortOrder: String
  var resourceType: String
  var colorHex: String
  var capacity: String
  var fullResourceGroup: String
  var notes: String

  static func new(orgId: UUID?) -> FacilityDraft {
    FacilityDraft(
      id: nil,
      orgId: orgId,
      name: "",
      isActive: true,
      sortOrder: "0",
      resourceType: "cage",
      colorHex: "#4D9EF9",
      capacity: "1",
      fullResourceGroup: "",
      notes: ""
    )
  }

  init(facility: SDFacility, orgId: UUID?) {
    self.id = facility.id
    self.orgId = facility.org_id ?? orgId
    self.name = facility.name
    self.isActive = facility.is_active
    self.sortOrder = String(facility.sort_order)
    self.resourceType = facility.resource_type ?? "cage"
    self.colorHex = facility.color_hex ?? "#4D9EF9"
    self.capacity = String(facility.capacity ?? 1)
    self.fullResourceGroup = ""
    self.notes = ""
  }

  private init(id: UUID?, orgId: UUID?, name: String, isActive: Bool, sortOrder: String, resourceType: String, colorHex: String, capacity: String, fullResourceGroup: String, notes: String) {
    self.id = id
    self.orgId = orgId
    self.name = name
    self.isActive = isActive
    self.sortOrder = sortOrder
    self.resourceType = resourceType
    self.colorHex = colorHex
    self.capacity = capacity
    self.fullResourceGroup = fullResourceGroup
    self.notes = notes
  }
}

private struct FacilityAdminEditorSheet: View {
  @Environment(\.dismiss) private var dismiss
  @State var draft: FacilityDraft
  let onSave: (FacilityDraft) -> Void

  var body: some View {
    NavigationStack {
      Form {
        Section("Resource") {
          TextField("Name", text: $draft.name)
          TextField("Type", text: $draft.resourceType)
          Toggle("Active / visible", isOn: $draft.isActive)
        }

        Section("Display") {
          TextField("Sort order", text: $draft.sortOrder)
          TextField("Color hex", text: $draft.colorHex)
          TextField("Capacity", text: $draft.capacity)
        }

        Section("Advanced") {
          TextField("Full-resource group (optional)", text: $draft.fullResourceGroup)
          TextField("Notes", text: $draft.notes, axis: .vertical)
        }
      }
      .navigationTitle(draft.id == nil ? "New Facility" : "Edit Facility")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            onSave(draft)
          }
          .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
    }
  }
}

private let orgRoleOptions = ["owner", "coach", "player", "parent"]
private let orgStatusOptions = ["active", "invited", "disabled"]

struct CreateMemberDraft: Equatable {
  var fullName = ""
  var email = ""
  var username = ""
  var password = ""
  var role = "player"

  var isValid: Bool {
    email.contains("@")
    && username.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3
    && password.count >= 8
  }
}

struct MemberDraft: Identifiable, Equatable {
  var id: UUID { userId }
  let userId: UUID
  var displayName: String
  var email: String
  var username: String
  var role: String
  var status: String

  init(member: SDOrgAdminMember) {
    self.userId = member.user_id
    self.displayName = member.displayName
    self.email = member.email ?? ""
    self.username = member.username ?? ""
    self.role = member.role
    self.status = member.status
  }
}

private struct CreateOrgMemberSheet: View {
  @Environment(\.dismiss) private var dismiss
  @State private var draft = CreateMemberDraft()
  let onCreate: (CreateMemberDraft) -> Void

  var body: some View {
    NavigationStack {
      Form {
        Section("Identity") {
          TextField("Full name", text: $draft.fullName)
          TextField("Email", text: $draft.email)
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .keyboardType(.emailAddress)
            #endif
          TextField("Org username", text: $draft.username)
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
          SecureField("Temporary password", text: $draft.password)
        }

        Section("Access") {
          Picker("Role", selection: $draft.role) {
            ForEach(orgRoleOptions, id: \.self) { role in
              Text(role.capitalized).tag(role)
            }
          }
          Text("Owners/coaches can administer this organization. Players and parents only see their app surfaces.")
            .font(.footnote)
            .foregroundStyle(DHDTheme.textSecondary)
        }
      }
      .navigationTitle("Create Org User")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Create") {
            onCreate(draft)
          }
          .disabled(!draft.isValid)
        }
      }
    }
  }
}

private struct EditOrgMemberSheet: View {
  @Environment(\.dismiss) private var dismiss
  @State var draft: MemberDraft
  let onSave: (MemberDraft) -> Void

  var body: some View {
    NavigationStack {
      Form {
        Section("Member") {
          Text(draft.displayName)
          if !draft.email.isEmpty {
            Text(draft.email)
              .foregroundStyle(DHDTheme.textSecondary)
          }
          Text(draft.userId.uuidString)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(DHDTheme.textSecondary)
        }

        Section("Org Login") {
          TextField("Username", text: $draft.username)
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
          Text("Usernames are unique inside this organization only.")
            .font(.footnote)
            .foregroundStyle(DHDTheme.textSecondary)
        }

        Section("Access") {
          Picker("Role", selection: $draft.role) {
            ForEach(orgRoleOptions, id: \.self) { role in
              Text(role.capitalized).tag(role)
            }
          }
          Picker("Status", selection: $draft.status) {
            ForEach(orgStatusOptions, id: \.self) { status in
              Text(status.capitalized).tag(status)
            }
          }
        }
      }
      .navigationTitle("Edit Member")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            onSave(draft)
          }
          .disabled(draft.username.trimmingCharacters(in: .whitespacesAndNewlines).count < 3)
        }
      }
    }
  }
}
