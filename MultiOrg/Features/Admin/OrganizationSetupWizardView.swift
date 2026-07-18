import SwiftUI

@MainActor
final class OrganizationSetupViewModel: ObservableObject {
  @Published private(set) var snapshot: SDOrganizationSetupSnapshot?
  @Published private(set) var isLoading = false
  @Published private(set) var isSaving = false
  @Published var errorText: String?
  @Published var toastText: String?
  @Published var selectedStep: SDOrganizationSetupStep = .basics

  private var requestToken: UUID?
  private var organizationId: UUID?
  private var pendingMutationRequestIds: [String: UUID] = [:]

  func load(service: SupabaseService?, organizationId: UUID) async {
    guard let service else { return }
    if self.organizationId != organizationId { pendingMutationRequestIds.removeAll() }
    let token = UUID()
    requestToken = token
    self.organizationId = organizationId
    isLoading = true
    errorText = nil
    do {
      let response = try await service.organizationSetup(organizationId: organizationId)
      guard accepts(response: response, token: token, organizationId: organizationId) else { return }
      snapshot = response
      selectedStep = response.session?.current_step ?? .basics
    } catch {
      guard requestToken == token, self.organizationId == organizationId,
            !SDApplicationErrorClassifier.isCancellation(error, taskIsCancelled: Task.isCancelled) else { return }
      errorText = SDApplicationErrorClassifier.alertMessage(for: error)
    }
    if requestToken == token { isLoading = false }
  }

  func mutate(
    service: SupabaseService?,
    organizationId: UUID,
    action: String,
    step: SDOrganizationSetupStep? = nil,
    field: String? = nil,
    payload: [String: SDJSONValue]? = nil,
    setupTestRunId: UUID? = nil,
    successMessage: String? = nil
  ) async {
    guard let service else { return }
    let operationKey = mutationOperationKey(action: action, step: step, field: field, payload: payload)
    let mutationRequestId = pendingMutationRequestIds[operationKey] ?? UUID()
    pendingMutationRequestIds[operationKey] = mutationRequestId
    let token = UUID()
    requestToken = token
    self.organizationId = organizationId
    isSaving = true
    errorText = nil
    do {
      let response = try await service.mutateOrganizationSetup(
        action: action,
        organizationId: organizationId,
        requestId: mutationRequestId,
        expectedVersion: snapshot?.session?.version,
        step: step,
        setupTestRunId: setupTestRunId,
        field: field,
        payload: payload
      )
      guard accepts(response: response, token: token, organizationId: organizationId) else { return }
      snapshot = response
      pendingMutationRequestIds.removeValue(forKey: operationKey)
      selectedStep = response.session?.current_step ?? selectedStep
      toastText = successMessage
    } catch {
      guard requestToken == token, self.organizationId == organizationId,
            !SDApplicationErrorClassifier.isCancellation(error, taskIsCancelled: Task.isCancelled) else { return }
      errorText = SDApplicationErrorClassifier.alertMessage(for: error)
    }
    if requestToken == token { isSaving = false }
  }

  private func mutationOperationKey(
    action: String,
    step: SDOrganizationSetupStep?,
    field: String?,
    payload: [String: SDJSONValue]?
  ) -> String {
    let encoded = (try? JSONEncoder().encode(payload))?.base64EncodedString() ?? ""
    return [action, step?.rawValue ?? "", field ?? "", encoded].joined(separator: "|")
  }

  private func accepts(
    response: SDOrganizationSetupSnapshot,
    token: UUID,
    organizationId: UUID
  ) -> Bool {
    SDOrganizationSetupRequestGuard.accepts(
      responseOrganizationId: response.organization.id,
      responseToken: token,
      activeOrganizationId: self.organizationId,
      currentToken: requestToken,
      taskIsCancelled: Task.isCancelled
    ) && response.organization.id == organizationId
  }
}

struct OrganizationSetupWizardView: View {
  let organizationId: UUID
  var organizationName: String? = nil

  @EnvironmentObject private var appState: AppState
  @Environment(\.dismiss) private var dismiss
  @StateObject private var model = OrganizationSetupViewModel()

  @State private var name = ""
  @State private var organizationType = "Travel Baseball"
  @State private var timezone = TimeZone.current.identifier
  @State private var defaultLocation = ""
  @State private var phone = ""
  @State private var website = ""
  @State private var supportEmail = ""
  @State private var seasonName = ""
  @State private var seasonStart = ""
  @State private var seasonEnd = ""
  @State private var teamName = ""
  @State private var teamColor = "#0D2445"
  @State private var staffInvites = ""
  @State private var playerFamilyCSV = "player_name,player_email,parent_email\n"
  @State private var registrationName = ""
  @State private var registrationFee = "0"
  @State private var facilityName = ""
  @State private var facilityType = "field"
  @State private var playerCoachMessages = true
  @State private var parentCoachMessages = true
  @State private var parentVisibility = true
  @State private var eventTitle = "First Practice"
  @State private var eventStart = ""
  @State private var eventEnd = ""
  @State private var hydratedOrganizationId: UUID?
  @State private var resetPreview: SDOrganizationSetupResetPreview?
  @State private var showingResetConfirmation = false
  @State private var showingSelectiveResetConfirmation = false

  private var setupTestConfiguration: SDOrganizationSetupTestConfiguration {
    .current()
  }

  private var hasSetupAuthority: Bool {
    appState.canAdminActiveOrg || appState.isPlatformAdmin
  }

  private var testModeVisible: Bool {
    setupTestConfiguration.allows(
      organizationId: organizationId,
      hasAuthority: hasSetupAuthority
    ) && model.snapshot?.test_mode == true
  }

  var body: some View {
    GeometryReader { proxy in
      Group {
        if model.isLoading && model.snapshot == nil {
          HPLoadingState(text: "Loading organization setup…")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = model.errorText, model.snapshot == nil {
          HPErrorState(
            title: "Setup unavailable",
            message: error,
            onRetry: { Task { await reload() } }
          )
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if proxy.size.width >= 840 {
          HStack(spacing: 0) {
            stepSidebar.frame(width: 280)
            Divider()
            wizardDetail
          }
        } else {
          VStack(spacing: 0) {
            compactStepPicker
            Divider()
            wizardDetail
          }
        }
      }
    }
    .navigationTitle("Organization Setup")
    .task(id: organizationId) { await reload() }
    .onChange(of: model.snapshot?.session?.version) { _, _ in hydrateFieldsIfNeeded() }
    .hpToast($model.toastText)
    .confirmationDialog(
      "Reset setup progress?",
      isPresented: $showingResetConfirmation,
      titleVisibility: .visible
    ) {
      Button("Reset Wizard Progress Only", role: .destructive) {
        Task { await resetProgressOnly() }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("This preserves all organization, season, team, roster, financial, communication, and baseball history.")
    }
    .confirmationDialog(
      "Delete setup-created test data?",
      isPresented: $showingSelectiveResetConfirmation,
      titleVisibility: .visible
    ) {
      Button("Delete Eligible Setup Test Data", role: .destructive) {
        Task {
          await perform(
            action: "reset_setup_test_data",
            success: "Eligible setup-created test data was removed. Protected history was preserved."
          )
          if model.errorText == nil { resetLocalWizardState() }
        }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Only records tagged to this guarded setup test run are eligible. Financial, registration, operations, communication, notification, and audit history cannot be deleted here.")
    }
  }

  private var stepSidebar: some View {
    VStack(alignment: .leading, spacing: HP.Space.md) {
      VStack(alignment: .leading, spacing: HP.Space.xs) {
        Text(organizationName ?? model.snapshot?.organization.name ?? "Organization")
          .font(HP.Font.headline)
        Text("Setup checklist")
          .font(HP.Font.caption)
          .foregroundStyle(HP.Color.textMuted)
      }
      .padding(.horizontal, HP.Space.md)
      .padding(.top, HP.Space.lg)
      ScrollView {
        VStack(spacing: HP.Space.xs) {
          ForEach(SDOrganizationSetupStep.allCases) { step in
            Button { select(step) } label: {
              HStack(spacing: HP.Space.sm) {
                Image(systemName: stepSymbol(step))
                  .foregroundStyle(stepColor(step))
                VStack(alignment: .leading, spacing: 2) {
                  Text(step.title).font(HP.Font.callout.weight(.semibold))
                  if step.isOptional {
                    Text("Optional").font(HP.Font.caption)
                  }
                }
                Spacer(minLength: 0)
              }
              .foregroundStyle(HP.Color.text)
              .padding(HP.Space.sm)
              .background(model.selectedStep == step ? HP.Color.surfaceRaised : Color.clear)
              .clipShape(RoundedRectangle(cornerRadius: HP.Radius.md))
            }
            .buttonStyle(.plain)
            .accessibilityValue(stepStateLabel(step))
          }
        }
        .padding(.horizontal, HP.Space.sm)
      }
      readinessSummary
      Spacer(minLength: 0)
    }
    .background(HP.Color.surface)
  }

  private var compactStepPicker: some View {
    Picker("Setup step", selection: Binding(
      get: { model.selectedStep },
      set: { select($0) }
    )) {
      ForEach(SDOrganizationSetupStep.allCases) { step in
        Text("\(step.title)\(step.isOptional ? " · Optional" : "")").tag(step)
      }
    }
    .pickerStyle(.menu)
    .padding(.horizontal, HP.Space.md)
    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
  }

  private var wizardDetail: some View {
    VStack(spacing: 0) {
      ScrollView {
        VStack(alignment: .leading, spacing: HP.Space.md) {
          HPWorkspaceHeader(
            model.selectedStep.title,
            orgLabel: model.snapshot?.organization.name ?? organizationName ?? "Organization",
            context: model.selectedStep.isOptional ? "Optional setup" : "Required for launch"
          )
          if let error = model.errorText {
            HPCard {
              HPErrorState(title: "Couldn’t save setup", message: error)
            }
          }
          stepContent
        }
        .frame(maxWidth: 760, alignment: .leading)
        .padding(HP.Space.lg)
        .frame(maxWidth: .infinity)
      }
      Divider()
      footer
    }
    .background(HP.Color.bg)
  }

  @ViewBuilder private var stepContent: some View {
    switch model.selectedStep {
    case .basics: basicsStep
    case .season: seasonStep
    case .teams: teamStep
    case .staff: staffStep
    case .playersFamilies: playersStep
    case .registrationFees: registrationStep
    case .facilities: facilityStep
    case .communication: communicationStep
    case .firstBaseballAction: firstActionStep
    case .reviewLaunch: reviewStep
    }
  }

  private var basicsStep: some View {
    setupCard("Organization identity", detail: "Used throughout schedules, communication, registration, and finance.") {
      TextField("Organization name", text: $name)
      TextField("Organization type", text: $organizationType)
      TextField("Timezone (for example America/New_York)", text: $timezone)
      TextField("Default location", text: $defaultLocation)
      TextField("Phone", text: $phone)
      TextField("Website host", text: $website)
      TextField("Support email", text: $supportEmail)
    }
  }

  private var seasonStep: some View {
    setupCard("Create the default season", detail: "The season becomes the scope for teams, rosters, events, registration, and reports.") {
      TextField("Season name", text: $seasonName)
      TextField("Start date (YYYY-MM-DD)", text: $seasonStart)
      TextField("End date (YYYY-MM-DD)", text: $seasonEnd)
      existingSummary(model.snapshot?.seasons.map(\.name) ?? [], empty: "No season exists yet.")
    }
  }

  private var teamStep: some View {
    setupCard("Create a team", detail: "Each active team must belong to the selected season.") {
      TextField("Team name", text: $teamName)
      TextField("Team color (hex)", text: $teamColor)
      existingSummary(model.snapshot?.teams.map(\.name) ?? [], empty: "No team exists yet.")
    }
  }

  private var staffStep: some View {
    setupCard("Prepare staff invitations", detail: "One email per line. Invitations remain a reviewable server draft until an administrator issues credentials from Members.") {
      TextEditor(text: $staffInvites).frame(minHeight: 150)
      Text("\(nonemptyLines(staffInvites).count) invitation candidate(s)")
        .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
    }
  }

  private var playersStep: some View {
    let validation = SDOrganizationSetupCSVValidator.validate(playerFamilyCSV)
    return setupCard("Import players and families", detail: "Paste CSV with player_name, player_email, and parent_email. The validated draft can be completed through authoritative roster and family-link workflows.") {
      TextEditor(text: $playerFamilyCSV).frame(minHeight: 190)
      if validation.errors.isEmpty {
        Label("\(validation.validRowCount) valid row(s)", systemImage: "checkmark.circle.fill")
          .foregroundStyle(HP.Color.success)
      } else {
        ForEach(validation.errors, id: \.self) { error in
          Label(error, systemImage: "exclamationmark.triangle")
            .font(HP.Font.caption).foregroundStyle(HP.Color.warning)
        }
      }
    }
  }

  private var registrationStep: some View {
    setupCard("Registration and fees", detail: "Creates a draft registration offering. It will not collect money or send provider messages until activated in Registration.") {
      TextField("Offering name", text: $registrationName)
      TextField("Fee in cents", text: $registrationFee)
    }
  }

  private var facilityStep: some View {
    setupCard("Facility resources", detail: "Create a field, cage, classroom, or other bookable organization resource.") {
      TextField("Facility name", text: $facilityName)
      Picker("Resource type", selection: $facilityType) {
        ForEach(["field", "cage", "classroom", "other"], id: \.self) { Text($0.capitalized).tag($0) }
      }
    }
  }

  private var communicationStep: some View {
    setupCard("Communication policy", detail: "Configure who can start conversations. No email, SMS, or push provider is invoked here.") {
      Toggle("Players may message coaches", isOn: $playerCoachMessages)
      Toggle("Parents may message coaches", isOn: $parentCoachMessages)
      Toggle("Require parent visibility for minors", isOn: $parentVisibility)
    }
  }

  private var firstActionStep: some View {
    setupCard("Schedule the first baseball action", detail: "Creates a draft practice in the authoritative team schedule.") {
      TextField("Event title", text: $eventTitle)
      TextField("Start (ISO 8601)", text: $eventStart)
      TextField("End (ISO 8601)", text: $eventEnd)
    }
  }

  private var reviewStep: some View {
    VStack(alignment: .leading, spacing: HP.Space.md) {
      HPCard {
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          HPSectionHeader("Launch readiness") {
            HPStatusBadge(
              text: model.snapshot?.readiness.ready == true ? "Ready" : "Needs attention",
              kind: model.snapshot?.readiness.ready == true ? .success : .warning
            )
          }
          Text("Launch requires an active organization, name and timezone, an active/default season, and an active team in that season. Optional steps never block launch.")
            .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
          ForEach(model.snapshot?.readiness.items ?? []) { item in
            Button { select(item.route_step) } label: {
              HStack {
                Image(systemName: item.complete ? "checkmark.circle.fill" : "circle")
                  .foregroundStyle(item.complete ? HP.Color.success : HP.Color.textMuted)
                Text(item.label)
                Spacer()
                Text(item.required ? "Required" : "Optional")
                  .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
              }
              .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
          }
        }
      }
      if testModeVisible { developerTestingCard }
    }
  }

  private var developerTestingCard: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Developer / Testing") { HPStatusBadge(text: "Marist test mode", kind: .warning) }
        Text("Guarded by exact organization UUID, environment, feature flag, and server authorization. Full organization reset is unavailable.")
          .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
        HPButton(title: "Reset Wizard Progress Only", systemImage: "arrow.counterclockwise", variant: .secondary) {
          showingResetConfirmation = true
        }
        HPButton(title: "Preview Selective Test Data Reset", systemImage: "doc.text.magnifyingglass", variant: .secondary) {
          Task { await previewTestReset() }
        }
        if let resetPreview {
          Text("\(resetPreview.candidates.count) setup-created test record(s) eligible. Payments, refunds, invoices, expenses, registration applications, operations, messages, notification delivery, and audit history remain protected.")
            .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
          if !resetPreview.candidates.isEmpty {
            HPButton(title: "Delete Eligible Setup Test Data", systemImage: "trash", variant: .secondary) {
              showingSelectiveResetConfirmation = true
            }
          }
        }
      }
    }
  }

  private var readinessSummary: some View {
    let complete = model.snapshot?.readiness.items.filter(\.complete).count ?? 0
    let total = model.snapshot?.readiness.items.count ?? 0
    return VStack(alignment: .leading, spacing: HP.Space.xs) {
      Text("\(complete) of \(total) checklist items")
        .font(HP.Font.caption.weight(.semibold))
      ProgressView(value: Double(complete), total: Double(max(total, 1)))
    }
    .padding(HP.Space.md)
  }

  private var footer: some View {
    HStack(spacing: HP.Space.sm) {
      HPButton(title: "Back", systemImage: "chevron.left", variant: .secondary) {
        select(model.selectedStep.previous)
      }
      .disabled(model.selectedStep == .basics || model.isSaving)
      if model.selectedStep.isOptional {
        HPButton(title: "Skip for Now", variant: .secondary) {
          Task { await perform(action: "skip_step", step: model.selectedStep) }
        }
        .disabled(model.isSaving)
      }
      Spacer(minLength: 0)
      HPButton(title: "Save & Exit", variant: .secondary) {
        Task {
          await perform(action: "dismiss")
          if model.errorText == nil { dismiss() }
        }
      }
      .disabled(model.isSaving)
      HPButton(
        title: model.selectedStep == .reviewLaunch ? "Launch Organization" : "Save & Continue",
        systemImage: model.selectedStep == .reviewLaunch ? "checkmark.seal.fill" : "arrow.right",
        variant: .primary,
        isLoading: model.isSaving
      ) {
        Task { await saveCurrentStep() }
      }
      .disabled(model.isSaving || (model.selectedStep == .reviewLaunch && model.snapshot?.readiness.ready != true))
    }
    .padding(HP.Space.md)
    .background(HP.Color.surface)
  }

  private func setupCard<Content: View>(
    _ title: String,
    detail: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.md) {
        HPSectionHeader(title)
        Text(detail).font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
        content()
      }
      .textFieldStyle(.roundedBorder)
    }
  }

  private func existingSummary(_ names: [String], empty: String) -> some View {
    Text(names.isEmpty ? empty : "Existing: \(names.joined(separator: ", "))")
      .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
  }

  private func nonemptyLines(_ value: String) -> [String] {
    value.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
  }

  private func stepStateLabel(_ step: SDOrganizationSetupStep) -> String {
    model.snapshot?.state(for: step).rawValue.replacingOccurrences(of: "_", with: " ").capitalized ?? "Not Started"
  }

  private func stepSymbol(_ step: SDOrganizationSetupStep) -> String {
    switch model.snapshot?.state(for: step) {
    case .complete: "checkmark.circle.fill"
    case .skipped: "forward.circle.fill"
    case .needsAttention: "exclamationmark.circle.fill"
    default: model.selectedStep == step ? "circle.inset.filled" : "circle"
    }
  }

  private func stepColor(_ step: SDOrganizationSetupStep) -> Color {
    switch model.snapshot?.state(for: step) {
    case .complete: HP.Color.success
    case .needsAttention: HP.Color.warning
    default: model.selectedStep == step ? HP.Color.accent : HP.Color.textMuted
    }
  }

  private func select(_ step: SDOrganizationSetupStep) {
    model.selectedStep = step
  }

  private func reload() async {
    await model.load(service: appState.supabase, organizationId: organizationId)
    hydrateFieldsIfNeeded()
  }

  private func hydrateFieldsIfNeeded() {
    guard let snapshot = model.snapshot, hydratedOrganizationId != snapshot.organization.id else { return }
    hydratedOrganizationId = snapshot.organization.id
    name = snapshot.organization.name
    organizationType = snapshot.organization.organization_type ?? organizationType
    timezone = snapshot.organization.timezone ?? timezone
    defaultLocation = snapshot.organization.default_location ?? ""
    phone = snapshot.organization.phone ?? ""
    website = snapshot.organization.website_host ?? ""
    supportEmail = snapshot.organization.support_email ?? ""
    if let season = snapshot.seasons.first(where: \.is_default) ?? snapshot.seasons.first {
      seasonName = season.name
      seasonStart = season.start_date ?? ""
      seasonEnd = season.end_date ?? ""
    }
    if let team = snapshot.teams.first { teamName = team.name; teamColor = team.color_hex ?? teamColor }
    let calendar = Calendar.current
    let start = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    let end = calendar.date(byAdding: .hour, value: 2, to: start) ?? start
    eventStart = ISO8601DateFormatter().string(from: start)
    eventEnd = ISO8601DateFormatter().string(from: end)
  }

  private func perform(
    action: String,
    step: SDOrganizationSetupStep? = nil,
    field: String? = nil,
    payload: [String: SDJSONValue]? = nil,
    success: String? = nil
  ) async {
    await model.mutate(
      service: appState.supabase,
      organizationId: organizationId,
      action: action,
      step: step,
      field: field,
      payload: payload,
      setupTestRunId: testModeVisible ? model.snapshot?.session?.id : nil,
      successMessage: success
    )
  }

  private func saveCurrentStep() async {
    switch model.selectedStep {
    case .basics:
      await perform(action: "save_basics", field: "basics", payload: [
        "name": .string(name), "organization_type": .string(organizationType),
        "timezone": .string(timezone), "default_location": .string(defaultLocation),
        "phone": .string(phone), "website_host": .string(website), "support_email": .string(supportEmail),
      ], success: "Organization basics saved.")
    case .season:
      await perform(action: "save_season", field: "season", payload: [
        "id": model.snapshot?.seasons.first(where: \.is_default).map { .string($0.id.uuidString) } ?? .null,
        "name": .string(seasonName), "start_date": .string(seasonStart), "end_date": .string(seasonEnd),
        "status": .string("active"), "is_default": .bool(true),
      ], success: "Season saved.")
    case .teams:
      guard let seasonId = model.snapshot?.seasons.first(where: \.is_default)?.id ?? model.snapshot?.seasons.first?.id else {
        model.errorText = "Create a season before adding a team."
        return
      }
      await perform(action: "save_team", field: "team", payload: [
        "id": model.snapshot?.teams.first.map { .string($0.id.uuidString) } ?? .null,
        "name": .string(teamName), "season_id": .string(seasonId.uuidString), "color_hex": .string(teamColor),
      ], success: "Team saved.")
    case .staff:
      await perform(action: "save_people_draft", step: .staff, field: "draft", payload: [
        "emails": .array(nonemptyLines(staffInvites).map(SDJSONValue.string)),
        "delivery_state": .string("draft_not_sent"),
      ], success: "Staff invitation draft saved.")
    case .playersFamilies:
      let validation = SDOrganizationSetupCSVValidator.validate(playerFamilyCSV)
      guard validation.errors.isEmpty else { model.errorText = validation.errors.first; return }
      await perform(action: "save_people_draft", step: .playersFamilies, field: "draft", payload: [
        "csv": .string(playerFamilyCSV), "valid_row_count": .int(validation.validRowCount),
        "import_state": .string("validated_draft"),
      ], success: "Player and family import draft saved.")
    case .registrationFees:
      guard let seasonId = model.snapshot?.seasons.first(where: \.is_default)?.id ?? model.snapshot?.seasons.first?.id else { return }
      await perform(action: "save_registration", field: "registration", payload: [
        "name": .string(registrationName), "season_id": .string(seasonId.uuidString),
        "team_id": model.snapshot?.teams.first.map { .string($0.id.uuidString) } ?? .null,
        "fee_cents": .int(Int(registrationFee) ?? 0),
      ], success: "Draft registration offering created.")
    case .facilities:
      await perform(action: "save_facility", field: "facility", payload: [
        "name": .string(facilityName), "resource_type": .string(facilityType), "capacity": .int(1),
      ], success: "Facility created.")
    case .communication:
      await perform(action: "save_communication", field: "communication", payload: [
        "player_to_coach_allowed": .bool(playerCoachMessages),
        "parent_to_coach_allowed": .bool(parentCoachMessages),
        "minor_parent_visibility_required": .bool(parentVisibility),
      ], success: "Communication policy saved.")
    case .firstBaseballAction:
      guard let seasonId = model.snapshot?.seasons.first(where: \.is_default)?.id ?? model.snapshot?.seasons.first?.id,
            let teamId = model.snapshot?.teams.first?.id else { return }
      await perform(action: "create_first_event", field: "event", payload: [
        "season_id": .string(seasonId.uuidString), "team_id": .string(teamId.uuidString),
        "title": .string(eventTitle), "event_type": .string("practice"),
        "start_at": .string(eventStart), "end_at": .string(eventEnd), "timezone": .string(timezone),
      ], success: "First practice drafted.")
    case .reviewLaunch:
      await perform(action: "complete", success: "Organization launched.")
    }
  }

  private func resetProgressOnly() async {
    await perform(action: "reset_progress", success: "Wizard progress reset. Organization data was preserved.")
    if model.errorText == nil { resetLocalWizardState() }
  }

  private func resetLocalWizardState() {
    hydratedOrganizationId = nil
    name = ""
    organizationType = "Travel Baseball"
    timezone = TimeZone.current.identifier
    defaultLocation = ""
    phone = ""
    website = ""
    supportEmail = ""
    seasonName = ""
    seasonStart = ""
    seasonEnd = ""
    teamName = ""
    teamColor = "#0D2445"
    staffInvites = ""
    playerFamilyCSV = "player_name,player_email,parent_email\n"
    registrationName = ""
    registrationFee = "0"
    facilityName = ""
    facilityType = "field"
    playerCoachMessages = true
    parentCoachMessages = true
    parentVisibility = true
    eventTitle = "First Practice"
    resetPreview = nil
    hydrateFieldsIfNeeded()
  }

  private func previewTestReset() async {
    do {
      guard let setupTestRunId = model.snapshot?.session?.id else { return }
      resetPreview = try await appState.supabase?.previewOrganizationSetupTestReset(
        organizationId: organizationId,
        setupTestRunId: setupTestRunId
      )
    } catch {
      model.errorText = SDApplicationErrorClassifier.alertMessage(for: error)
    }
  }
}

enum SDOrganizationSetupCSVValidator {
  struct Result: Equatable, Sendable {
    let validRowCount: Int
    let errors: [String]
  }

  static func validate(_ csv: String) -> Result {
    let lines = csv.split(whereSeparator: \.isNewline).map(String.init)
    guard let header = lines.first else { return Result(validRowCount: 0, errors: ["Add a CSV header row."]) }
    let columns = header.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
    let required = ["player_name", "player_email", "parent_email"]
    let missing = required.filter { !columns.contains($0) }
    guard missing.isEmpty else { return Result(validRowCount: 0, errors: ["Missing column(s): \(missing.joined(separator: ", "))."]) }
    var emails = Set<String>()
    var errors: [String] = []
    var valid = 0
    for (offset, line) in lines.dropFirst().enumerated() where !line.trimmingCharacters(in: .whitespaces).isEmpty {
      let values = line.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
      guard values.count == columns.count else { errors.append("Row \(offset + 2) has the wrong number of columns."); continue }
      let playerEmail = values[columns.firstIndex(of: "player_email")!].lowercased()
      let parentEmail = values[columns.firstIndex(of: "parent_email")!].lowercased()
      guard playerEmail.contains("@"), parentEmail.contains("@") else { errors.append("Row \(offset + 2) has an invalid email."); continue }
      guard emails.insert(playerEmail).inserted else { errors.append("Row \(offset + 2) duplicates a player email."); continue }
      valid += 1
    }
    return Result(validRowCount: valid, errors: errors)
  }
}

struct OrganizationSetupOverviewCard: View {
  let organizationId: UUID
  let organizationName: String
  @EnvironmentObject private var appState: AppState
  @State private var snapshot: SDOrganizationSetupSnapshot?
  @State private var errorText: String?
  @State private var requestToken: UUID?

  var body: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Organization setup") {
          HPStatusBadge(
            text: statusLabel,
            kind: snapshot?.readiness.ready == true ? .success : .warning
          )
        }
        if let snapshot {
          let required = snapshot.readiness.items.filter(\.required)
          let complete = required.filter(\.complete).count
          Text("\(complete) of \(required.count) launch requirements complete")
            .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
          ProgressView(value: Double(complete), total: Double(max(required.count, 1)))
          NavigationLink {
            OrganizationSetupWizardView(
              organizationId: organizationId,
              organizationName: organizationName
            )
          } label: {
            Label(actionLabel, systemImage: "arrow.right.circle.fill")
              .font(HP.Font.callout.weight(.semibold))
              .foregroundStyle(HP.Color.accent)
              .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
          }
        } else if let errorText {
          HPErrorState(
            title: "Setup status unavailable",
            message: errorText,
            onRetry: { Task { await load() } }
          )
        } else {
          HPLoadingState(text: "Checking setup readiness…")
        }
      }
    }
    .task(id: organizationId) { await load() }
  }

  private var statusLabel: String {
    if snapshot?.session?.status == .completed { return "Launched" }
    if snapshot?.readiness.ready == true { return "Ready" }
    if snapshot?.session?.status == .dismissed { return "Saved" }
    return "Incomplete"
  }

  private var actionLabel: String {
    switch snapshot?.session?.status {
    case .completed: "Review Setup"
    case .notStarted, .none: "Start Setup"
    default: "Continue Setup"
    }
  }

  private func load() async {
    guard let service = appState.supabase else { return }
    let token = UUID()
    requestToken = token
    errorText = nil
    do {
      let response = try await service.organizationSetup(organizationId: organizationId)
      guard requestToken == token, response.organization.id == organizationId,
            !Task.isCancelled else { return }
      snapshot = response
    } catch {
      guard requestToken == token,
            !SDApplicationErrorClassifier.isCancellation(error, taskIsCancelled: Task.isCancelled) else { return }
      errorText = SDApplicationErrorClassifier.alertMessage(for: error)
    }
  }
}
