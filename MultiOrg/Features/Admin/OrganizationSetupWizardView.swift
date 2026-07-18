import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

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
      errorText = SDOrganizationSetupErrorMapper.message(for: error)
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
      errorText = SDOrganizationSetupErrorMapper.message(for: error)
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
  @State private var seasonStart = Date()
  @State private var seasonEnd = Calendar.current.date(byAdding: .month, value: 4, to: Date()) ?? Date()
  @State private var pendingTeams: [SDPendingTeamDraft] = []
  @State private var staffInvites: [SDStaffInviteDraft] = []
  @State private var bulkStaffEmails = ""
  @State private var invitationLinks: [SDOrganizationInvitationContext: SDOrganizationInvitationLink] = [:]
  @State private var generatedInvitationURLs: [SDOrganizationInvitationContext: String] = [:]
  @State private var invitationActionInFlight: SDOrganizationInvitationContext?
  @State private var invitationLoadError: String?
  @State private var playerFamilyCSV = "player_name,player_email,parent_email\n"
  @State private var manualPlayerName = ""
  @State private var registrationChoice: SDRegistrationSetupChoice = .later
  @State private var registrationName = ""
  @State private var registrationFee = ""
  @State private var registrationCapacity = ""
  @State private var registrationOpenDate = Date()
  @State private var registrationCloseDate = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
  @State private var facilityName = ""
  @State private var facilityType = "field"
  @State private var playerCoachMessages = true
  @State private var parentCoachMessages = true
  @State private var parentVisibility = true
  @State private var eventTitle = ""
  @State private var eventDate = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
  @State private var eventArrivalTime = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
  @State private var eventStartTime = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
  @State private var eventEndTime = Calendar.current.date(byAdding: .hour, value: 3, to: Date()) ?? Date()
  @State private var eventLocation = ""
  @State private var eventTeamId: UUID?
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
      OrganizationSetupWizardContentContainer(step: model.selectedStep) {
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
      HPFormField(label: "Organization name", text: $name, placeholder: "Example: Marist Red Foxes", error: name.sdNilIfBlank == nil ? "Enter an organization name." : nil)
      HPFormField(label: "Organization type", text: $organizationType, placeholder: "Example: Travel baseball")
      VStack(alignment: .leading, spacing: HP.Space.xs) {
        Text("TIMEZONE").font(HP.Font.eyebrow).foregroundStyle(HP.Color.textMuted)
        Picker("Timezone", selection: $timezone) {
          ForEach(Self.commonTimezones, id: \.self) { identifier in
            Text(SDOrganizationSetupTimeCodec.timeZoneDisplayName(identifier: identifier) ?? identifier).tag(identifier)
          }
        }.pickerStyle(.menu).frame(minHeight: 44)
        Text("Scheduling uses this timezone even when a device is elsewhere.").font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
      }
      HPFormField(label: "Default location", text: $defaultLocation, placeholder: "Example: Main baseball complex")
      HPFormField(label: "Phone", text: $phone, placeholder: "Organization contact number")
      HPFormField(label: "Website", text: $website, placeholder: "Example: maristbaseball.org")
      HPFormField(label: "Support email", text: $supportEmail, placeholder: "Example: help@organization.org")
    }
  }

  private var seasonStep: some View {
    setupCard("Create the default season", detail: "The season becomes the scope for teams, rosters, events, registration, and reports.") {
      HPFormField(label: "Season name", text: $seasonName, placeholder: "Example: Fall 2026")
      labeledDatePicker("Start date", selection: $seasonStart)
      labeledDatePicker("End date", selection: $seasonEnd)
      existingSummary(model.snapshot?.seasons.map(\.name) ?? [], empty: "No season exists yet.")
    }
  }

  private var teamStep: some View {
    setupCard("Teams", detail: "Create one or more teams for this season. Existing teams are reused and are never duplicated on retry.") {
      if let teams = model.snapshot?.teams, !teams.isEmpty {
        VStack(alignment: .leading, spacing: HP.Space.xs) {
          Text("EXISTING TEAMS").font(HP.Font.eyebrow).foregroundStyle(HP.Color.textMuted)
          ForEach(teams) { team in
            HStack {
              Image(systemName: "checkmark.circle.fill").foregroundStyle(HP.Color.success)
              VStack(alignment: .leading) {
                Text(team.name).font(HP.Font.callout.weight(.semibold))
                Text([team.age_group, team.competitive_level].compactMap { $0 }.joined(separator: " · "))
                  .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
                if let rosterCount = team.roster_count {
                  Text("\(rosterCount) rostered")
                    .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
                }
              }
              Spacer()
              HPStatusBadge(text: "Reused", kind: .success)
              Button("Edit") { beginEditing(team) }
                .disabled(pendingTeams.contains { $0.existingTeamId == team.id })
            }.frame(minHeight: 44)
          }
        }
      }
      ForEach($pendingTeams) { $team in
        pendingTeamCard(team: $team)
      }
      HPButton(title: "Add Team", systemImage: "plus", variant: .secondary) {
        pendingTeams.append(SDPendingTeamDraft())
      }
    }
  }

  private var staffStep: some View {
    setupCard("Staff", detail: "Invite coaches and staff now, or continue and add them later. Setup saves a reviewable draft and does not send messages.") {
      invitationLinkCard(context: .staff)
      ForEach($staffInvites) { $invite in staffInviteCard(invite: $invite) }
      HPButton(title: "Add Staff Member", systemImage: "plus", variant: .secondary) {
        staffInvites.append(SDStaffInviteDraft())
      }
      DisclosureGroup("Import Multiple Emails") {
        HPFormField(label: "Email addresses", text: $bulkStaffEmails, kind: .multiline, placeholder: "One email address per line", helper: "Imported addresses are added to the draft; nothing is sent.")
      }
    }
  }

  private var playersStep: some View {
    let validation = SDOrganizationSetupCSVValidator.validate(playerFamilyCSV)
    return setupCard("Players & Families", detail: "Share a secure organization invite. The signed link preserves family context through sign-in without exposing organization or role parameters.") {
      invitationLinkCard(context: .family)
      DisclosureGroup("Add a player manually") {
        HPFormField(label: "Player name", text: $manualPlayerName, placeholder: "Player’s full name", helper: "You can complete roster details later.")
      }
      DisclosureGroup("Advanced: Import CSV") {
        HPFormField(label: "Player and family CSV", text: $playerFamilyCSV, kind: .multiline, placeholder: "player_name,player_email,parent_email")
        if validation.errors.isEmpty {
          Label("\(validation.validRowCount) valid row(s)", systemImage: "checkmark.circle.fill").foregroundStyle(HP.Color.success)
        } else {
          ForEach(validation.errors, id: \.self) { error in
            Label(error, systemImage: "exclamationmark.triangle").font(HP.Font.caption).foregroundStyle(HP.Color.warning)
          }
        }
      }
    }
  }

  private var registrationStep: some View {
    setupCard("Registration & Fees", detail: "Will you collect registration or team fees through Home Plate?") {
      Picker("Registration setup", selection: $registrationChoice) {
        ForEach(SDRegistrationSetupChoice.allCases) { Text($0.rawValue).tag($0) }
      }.pickerStyle(.segmented)
      if registrationChoice == .configureNow {
        HPFormField(label: "Offering name", text: $registrationName, placeholder: "Example: Fall 2026 registration")
        currencyField
        HPFormField(label: "Capacity", text: $registrationCapacity, placeholder: "Optional roster limit")
        labeledDatePicker("Open date", selection: $registrationOpenDate)
        labeledDatePicker("Close date", selection: $registrationCloseDate)
        labeledValue("Season", value: seasonName.sdNilIfBlank ?? "Default season")
        labeledValue("Team scope", value: "All teams")
        labeledValue("State", value: "Draft")
      } else {
        Text(registrationChoice == .later ? "You can configure registration later from Registration." : "Home Plate will not configure an offering during setup.")
          .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
      }
    }
  }

  private var facilityStep: some View {
    setupCard("Facility resources", detail: "Create a field, cage, classroom, or other bookable organization resource.") {
      HPFormField(label: "Facility name", text: $facilityName, placeholder: "Example: McCann Field")
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
    setupCard("First Baseball Action", detail: "Create a draft event in the organization timezone. Timestamps are converted to UTC only when saved.") {
      labeledValue("Event type", value: "Practice")
      HPFormField(label: "Practice name", text: $eventTitle, placeholder: "Example: Monday team practice")
      labeledDatePicker("Date", selection: $eventDate)
      labeledTimePicker("Arrival time", selection: $eventArrivalTime)
      labeledTimePicker("Start time", selection: $eventStartTime)
      labeledTimePicker("End time", selection: $eventEndTime)
      labeledValue("Organization timezone", value: SDOrganizationSetupTimeCodec.timeZoneDisplayName(identifier: timezone) ?? "Timezone required")
      labeledTeamPicker
      HPFormField(label: "Location", text: $eventLocation, placeholder: "Example: Main field")
      if eventTiming == nil {
        Label(TimeZone(identifier: timezone) == nil ? "Return to Organization Basics and choose a valid timezone." : "Arrival must be at or before start, and end must be after start.", systemImage: "exclamationmark.triangle")
          .font(HP.Font.caption).foregroundStyle(HP.Color.warning)
      }
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
        HPButton(title: "Reset Setup Test Data", systemImage: "doc.text.magnifyingglass", variant: .secondary) {
          Task { await previewTestReset() }
        }
        HPButton(title: "Review Setup State", systemImage: "checklist", variant: .secondary) {
          model.selectedStep = .reviewLaunch
        }
        Text("Selective cleanup always shows a preview before confirmation.")
          .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
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
    ViewThatFits(in: .horizontal) {
      footerActions
      VStack(spacing: HP.Space.sm) { footerActions }
    }
    .padding(HP.Space.md)
    .background(HP.Color.surface)
  }

  private var footerActions: some View {
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
  }

  private static let commonTimezones = [
    "America/New_York", "America/Chicago", "America/Denver", "America/Los_Angeles", "UTC",
  ]

  private func pendingTeamCard(team: Binding<SDPendingTeamDraft>) -> some View {
    let draft = team.wrappedValue
    return VStack(alignment: .leading, spacing: HP.Space.sm) {
      HStack {
        Text(draft.existingTeamId == nil ? "NEW TEAM" : "EDIT TEAM").font(HP.Font.eyebrow).foregroundStyle(HP.Color.textMuted)
        Spacer()
        Button(role: .destructive) { pendingTeams.removeAll { $0.id == draft.id } } label: {
          Label(draft.existingTeamId == nil ? "Remove" : "Cancel edit", systemImage: draft.existingTeamId == nil ? "trash" : "xmark")
        }.buttonStyle(.plain)
      }
      HPFormField(label: "Team name", text: team.name, placeholder: "Example: 14U Red Foxes", error: draft.name.isEmpty ? nil : draft.validationError)
      HPFormField(label: "Age group", text: team.ageGroup, placeholder: "Example: 14U")
      HPFormField(label: "Level", text: team.level, placeholder: "Example: Travel")
      HPFormField(label: "Roster capacity", text: team.rosterCapacity, placeholder: "Optional", error: draft.rosterCapacity.isEmpty ? nil : draft.validationError)
      labeledValue("Season", value: seasonName.sdNilIfBlank ?? "Default season")
    }
    .padding(HP.Space.sm)
    .background(RoundedRectangle(cornerRadius: HP.Radius.md).fill(HP.Color.surfaceRaised))
  }

  private func staffInviteCard(invite: Binding<SDStaffInviteDraft>) -> some View {
    let draft = invite.wrappedValue
    let duplicate = staffInvites.filter { !$0.normalizedEmail.isEmpty && $0.normalizedEmail == draft.normalizedEmail }.count > 1
    return VStack(alignment: .leading, spacing: HP.Space.sm) {
      HStack {
        Text("STAFF INVITATION").font(HP.Font.eyebrow).foregroundStyle(HP.Color.textMuted)
        Spacer()
        Button(role: .destructive) { staffInvites.removeAll { $0.id == draft.id } } label: {
          Label("Remove", systemImage: "trash")
        }.buttonStyle(.plain)
      }
      HPFormField(
        label: "Email address",
        text: invite.email,
        placeholder: "coach@example.com",
        error: duplicate ? "This email is already in the invitation draft." : (!draft.email.isEmpty && !draft.hasValidEmail ? "Enter a valid email address." : nil)
      )
      HPFormField(label: "Display name", text: invite.displayName, placeholder: "Optional")
      labeledPicker("Role or responsibility", selection: invite.responsibility) {
        ForEach(SDStaffResponsibility.allCases) { Text($0.title).tag($0) }
      }
      labeledPicker("Team", selection: invite.teamId) {
        Text("Assign later").tag(UUID?.none)
        ForEach(model.snapshot?.teams ?? []) { Text($0.name).tag(Optional($0.id)) }
      }
      Text("Existing organization members are assigned through the authoritative membership flow instead of being duplicated.")
        .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
    }
    .padding(HP.Space.sm)
    .background(RoundedRectangle(cornerRadius: HP.Radius.md).fill(HP.Color.surfaceRaised))
  }

  private func invitationLinkCard(context: SDOrganizationInvitationContext) -> some View {
    let link = invitationLinks[context]
    let rawURL = generatedInvitationURLs[context]
    return VStack(alignment: .leading, spacing: HP.Space.sm) {
      if let invitationLoadError {
        HPErrorState(
          title: "Invitation links unavailable",
          message: invitationLoadError,
          onRetry: { Task { await loadInvitationLinks() } }
        )
      } else {
        HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text(context.title).font(HP.Font.callout.weight(.semibold))
          Text(link?.isActive == true ? "Active until \(expirationLabel(link?.expires_at))" : "No active link")
            .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
        }
        Spacer()
        HPStatusBadge(text: link?.isActive == true ? "Active" : "Disabled", kind: link?.isActive == true ? .success : .neutral)
      }
        if let rawURL {
          Text("For security, the complete link is shown only after generation or rotation.")
            .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
          HStack {
            HPButton(title: "Copy \(context == .family ? "Family" : "Coach") Invite Link", systemImage: "doc.on.doc", variant: .secondary) {
              copyToPasteboard(rawURL)
              model.toastText = "Invitation link copied."
            }
            if let url = URL(string: rawURL) { ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") } }
          }
        }
        HStack {
          HPButton(title: link == nil ? "Generate Link" : "Regenerate Link", systemImage: "arrow.clockwise", variant: .secondary, isLoading: invitationActionInFlight == context) {
            Task { await generateInvitation(context: context, rotating: link != nil) }
          }
          if let link, link.revoked_at == nil {
            Button("Disable Link", role: .destructive) { Task { await revokeInvitation(link) } }
          }
        }
      }
    }
    .padding(HP.Space.sm)
    .background(RoundedRectangle(cornerRadius: HP.Radius.md).fill(HP.Color.surfaceRaised))
  }

  private var currencyField: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("REGISTRATION FEE").font(HP.Font.eyebrow).foregroundStyle(HP.Color.textMuted)
      HStack {
        Text("$").font(HP.Font.body.weight(.semibold)).accessibilityHidden(true)
        TextField("0.00", text: $registrationFee).textFieldStyle(.plain)
          #if os(iOS)
          .keyboardType(.decimalPad)
          #endif
          .accessibilityLabel("Registration fee in dollars")
      }
      .padding(.horizontal, HP.Space.sm).frame(minHeight: 44)
      .background(RoundedRectangle(cornerRadius: HP.Radius.md).fill(HP.Color.input))
      .overlay(RoundedRectangle(cornerRadius: HP.Radius.md).strokeBorder(registrationFeeError == nil ? HP.Color.border : HP.Color.danger))
      Text(registrationFeeError ?? "You can change this later before opening registration.")
        .font(HP.Font.caption).foregroundStyle(registrationFeeError == nil ? HP.Color.textMuted : HP.Color.danger)
    }
  }

  private var registrationFeeError: String? {
    guard !registrationFee.isEmpty else { return nil }
    return SDPaymentRequestCreateDraft.parseUSDCents(registrationFee) == nil
      ? "Enter a nonnegative amount with no more than two decimal places."
      : nil
  }

  private func labeledDatePicker(_ label: String, selection: Binding<Date>) -> some View {
    labeledPickerContainer(label) {
      DatePicker(label, selection: selection, displayedComponents: .date).labelsHidden()
        .environment(\.timeZone, TimeZone(identifier: timezone) ?? .gmt)
    }
  }

  private func labeledTimePicker(_ label: String, selection: Binding<Date>) -> some View {
    labeledPickerContainer(label) {
      DatePicker(label, selection: selection, displayedComponents: .hourAndMinute).labelsHidden()
        .environment(\.timeZone, TimeZone(identifier: timezone) ?? .gmt)
    }
  }

  private func labeledPicker<Selection: Hashable, Content: View>(
    _ label: String,
    selection: Binding<Selection>,
    @ViewBuilder content: () -> Content
  ) -> some View {
    labeledPickerContainer(label) { Picker(label, selection: selection, content: content).pickerStyle(.menu) }
  }

  private func labeledPickerContainer<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(label.uppercased()).font(HP.Font.eyebrow).foregroundStyle(HP.Color.textMuted)
      content().frame(minHeight: 44)
    }
  }

  private func labeledValue(_ label: String, value: String) -> some View {
    HStack { Text(label).font(HP.Font.caption).foregroundStyle(HP.Color.textMuted); Spacer(); Text(value).font(HP.Font.callout) }
      .frame(minHeight: 44)
  }

  private var labeledTeamPicker: some View {
    labeledPicker("Team", selection: $eventTeamId) {
      Text("Choose a team").tag(UUID?.none)
      ForEach(model.snapshot?.teams ?? []) { Text($0.name).tag(Optional($0.id)) }
    }
  }

  private var eventTiming: (arrival: Date, start: Date, end: Date)? {
    guard let arrival = SDOrganizationSetupTimeCodec.instant(date: eventDate, time: eventArrivalTime, timeZoneIdentifier: timezone),
          let start = SDOrganizationSetupTimeCodec.instant(date: eventDate, time: eventStartTime, timeZoneIdentifier: timezone),
          let end = SDOrganizationSetupTimeCodec.instant(date: eventDate, time: eventEndTime, timeZoneIdentifier: timezone),
          SDOrganizationSetupTimeCodec.validates(arrival: arrival, start: start, end: end) else { return nil }
    return (arrival, start, end)
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
    await loadInvitationLinks()
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
      seasonStart = season.start_date.flatMap(Self.setupDate) ?? seasonStart
      seasonEnd = season.end_date.flatMap(Self.setupDate) ?? seasonEnd
    }
    eventTeamId = snapshot.teams.first?.id
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
        "name": .string(seasonName), "start_date": .string(Self.setupDateString(seasonStart)), "end_date": .string(Self.setupDateString(seasonEnd)),
        "status": .string("active"), "is_default": .bool(true),
      ], success: "Season saved.")
    case .teams:
      guard let seasonId = model.snapshot?.seasons.first(where: \.is_default)?.id ?? model.snapshot?.seasons.first?.id else {
        model.errorText = "Create a season before adding a team."
        return
      }
      guard pendingTeams.allSatisfy({ $0.validationError == nil }) else { model.errorText = pendingTeams.compactMap(\.validationError).first; return }
      if pendingTeams.isEmpty, model.snapshot?.teams.isEmpty == false {
        await perform(action: "navigate", step: .staff, success: "Existing teams selected.")
      } else {
        let items = pendingTeams.map { team in
          SDJSONValue.object([
            "id": team.existingTeamId.map { .string($0.uuidString) } ?? .null,
            "name": .string(team.name), "season_id": .string(seasonId.uuidString),
            "age_group": .string(team.ageGroup), "competitive_level": .string(team.level),
            "roster_capacity": team.rosterCapacity.isEmpty ? .null : .int(Int(team.rosterCapacity) ?? 0),
          ])
        }
        await perform(action: "save_teams", field: "teams", payload: ["items": .array(items)], success: "Teams saved.")
        if model.errorText == nil { pendingTeams.removeAll() }
      }
    case .staff:
      let bulk = nonemptyLines(bulkStaffEmails).map { email -> SDStaffInviteDraft in var item = SDStaffInviteDraft(); item.email = email; return item }
      let combined = staffInvites + bulk
      guard combined.allSatisfy(\.hasValidEmail) else { model.errorText = "Enter a valid email address for each staff member."; return }
      guard Set(combined.map(\.normalizedEmail)).count == combined.count else { model.errorText = "Remove duplicate staff email addresses before continuing."; return }
      await perform(action: "save_people_draft", step: .staff, field: "draft", payload: [
        "invitations": .array(combined.map { invite in .object([
          "email": .string(invite.normalizedEmail), "display_name": .string(invite.displayName),
          "responsibility": .string(invite.responsibility.rawValue),
          "team_id": invite.teamId.map { .string($0.uuidString) } ?? .null,
        ]) }),
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
      guard registrationChoice == .configureNow else {
        await perform(action: "skip_step", step: .registrationFees, success: registrationChoice == .later ? "Registration deferred." : "Registration setup declined.")
        return
      }
      guard let seasonId = model.snapshot?.seasons.first(where: \.is_default)?.id ?? model.snapshot?.seasons.first?.id else { return }
      guard let feeCents = SDPaymentRequestCreateDraft.parseUSDCents(registrationFee) else { model.errorText = "Enter a nonnegative registration fee with no more than two decimal places."; return }
      await perform(action: "save_registration", field: "registration", payload: [
        "name": .string(registrationName), "season_id": .string(seasonId.uuidString),
        "team_id": model.snapshot?.teams.first.map { .string($0.id.uuidString) } ?? .null,
        "fee_cents": .int(feeCents),
        "capacity": registrationCapacity.isEmpty ? .null : .int(Int(registrationCapacity) ?? 0),
        "opens_at": .string(SDOrganizationSetupTimeCodec.isoUTC(registrationOpenDate)),
        "closes_at": .string(SDOrganizationSetupTimeCodec.isoUTC(registrationCloseDate)),
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
            let teamId = eventTeamId, let timing = eventTiming else { model.errorText = "Choose a team and valid event times before continuing."; return }
      await perform(action: "create_first_event", field: "event", payload: [
        "season_id": .string(seasonId.uuidString), "team_id": .string(teamId.uuidString),
        "title": .string(eventTitle), "event_type": .string("practice"),
        "arrival_at": .string(SDOrganizationSetupTimeCodec.isoUTC(timing.arrival)),
        "start_at": .string(SDOrganizationSetupTimeCodec.isoUTC(timing.start)),
        "end_at": .string(SDOrganizationSetupTimeCodec.isoUTC(timing.end)),
        "timezone": .string(timezone), "location_name": .string(eventLocation),
      ], success: "First practice drafted.")
    case .reviewLaunch:
      await perform(action: "complete", success: "Organization launched.")
    }
  }

  private func resetProgressOnly() async {
    await perform(action: "reset_progress", success: "Wizard progress reset. Organization data was preserved.")
    if model.errorText == nil { resetLocalWizardState() }
  }

  private func loadInvitationLinks() async {
    guard let service = appState.supabase else { return }
    do {
      let links = try await service.organizationInvitationLinks(organizationId: organizationId)
      guard !Task.isCancelled, appState.activeOrgId == organizationId else { return }
      invitationLoadError = nil
      invitationLinks = Dictionary(uniqueKeysWithValues: SDOrganizationInvitationContext.allCases.compactMap { context in
        links.first(where: { $0.invitation_context == context && $0.revoked_at == nil }).map { (context, $0) }
      })
    } catch {
      guard !SDApplicationErrorClassifier.isCancellation(error, taskIsCancelled: Task.isCancelled) else { return }
      // Invitation service availability is scoped to the invitation cards and
      // must not make the rest of organization setup unusable.
      SDApplicationErrorClassifier.log(error, functionName: "organization-invitations")
      invitationLoadError = SDApplicationErrorClassifier.alertMessage(for: error)
    }
  }

  private func generateInvitation(context: SDOrganizationInvitationContext, rotating: Bool) async {
    guard let service = appState.supabase else { return }
    invitationActionInFlight = context
    defer { if invitationActionInFlight == context { invitationActionInFlight = nil } }
    do {
      let defaultStaff = staffInvites.first
      let response = try await service.generateOrganizationInvitationLink(
        organizationId: organizationId,
        context: context,
        rotating: rotating,
        teamId: context == .staff ? defaultStaff?.teamId : nil,
        responsibilities: context == .staff ? defaultStaff.map { [$0.responsibility] } ?? [] : []
      )
      guard !Task.isCancelled, appState.activeOrgId == organizationId else { return }
      invitationLinks[context] = response.link
      generatedInvitationURLs[context] = response.invitation_url
      model.toastText = rotating ? "Invitation link regenerated. The previous link is disabled." : "Invitation link generated."
    } catch {
      guard !SDApplicationErrorClassifier.isCancellation(error, taskIsCancelled: Task.isCancelled) else { return }
      model.errorText = SDApplicationErrorClassifier.alertMessage(for: error)
    }
  }

  private func revokeInvitation(_ link: SDOrganizationInvitationLink) async {
    guard let service = appState.supabase else { return }
    invitationActionInFlight = link.invitation_context
    defer { if invitationActionInFlight == link.invitation_context { invitationActionInFlight = nil } }
    do {
      let response = try await service.revokeOrganizationInvitationLink(organizationId: organizationId, linkId: link.id)
      guard !Task.isCancelled, appState.activeOrgId == organizationId else { return }
      invitationLinks[link.invitation_context] = response.link
      generatedInvitationURLs[link.invitation_context] = nil
      model.toastText = "Invitation link disabled."
    } catch {
      guard !SDApplicationErrorClassifier.isCancellation(error, taskIsCancelled: Task.isCancelled) else { return }
      model.errorText = SDApplicationErrorClassifier.alertMessage(for: error)
    }
  }

  private func expirationLabel(_ value: String?) -> String {
    guard let value, let date = SDTeamEventDateParser.date(value) else { return "its expiration date" }
    return date.formatted(date: .abbreviated, time: .shortened)
  }

  private func copyToPasteboard(_ value: String) {
    #if canImport(UIKit)
    UIPasteboard.general.string = value
    #elseif canImport(AppKit)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(value, forType: .string)
    #endif
  }

  private static func setupDateString(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = .gmt
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
  }

  private static func setupDate(_ value: String) -> Date? {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = .gmt
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.date(from: value)
  }

  private func beginEditing(_ team: SDTeam) {
    guard !pendingTeams.contains(where: { $0.existingTeamId == team.id }) else { return }
    var draft = SDPendingTeamDraft(existingTeamId: team.id)
    draft.name = team.name
    draft.ageGroup = team.age_group ?? ""
    draft.level = team.competitive_level ?? ""
    draft.rosterCapacity = team.roster_capacity.map(String.init) ?? ""
    pendingTeams.append(draft)
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
    seasonStart = Date()
    seasonEnd = Calendar.current.date(byAdding: .month, value: 4, to: Date()) ?? Date()
    pendingTeams = []
    staffInvites = []
    bulkStaffEmails = ""
    playerFamilyCSV = "player_name,player_email,parent_email\n"
    registrationName = ""
    registrationFee = ""
    registrationChoice = .later
    facilityName = ""
    facilityType = "field"
    playerCoachMessages = true
    parentCoachMessages = true
    parentVisibility = true
    eventTitle = ""
    eventTeamId = model.snapshot?.teams.first?.id
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

private struct OrganizationSetupWizardContentContainer<Content: View>: View {
  let step: SDOrganizationSetupStep
  @ViewBuilder let content: Content

  init(step: SDOrganizationSetupStep, @ViewBuilder content: () -> Content) {
    self.step = step
    self.content = content()
  }

  var body: some View {
    ScrollView {
      content
        .frame(maxWidth: 760, alignment: .leading)
        .padding(.horizontal, HP.Space.lg)
        .padding(.bottom, HP.Space.lg)
        .frame(maxWidth: .infinity)
    }
    .id(step)
    .contentMargins(.top, HP.Space.lg, for: .scrollContent)
    .scrollClipDisabled(false)
    .accessibilityIdentifier("organization-setup-content-\(step.rawValue)")
  }
}

struct PendingOrganizationInvitationView: View {
  @EnvironmentObject private var appState: AppState
  @Environment(\.dismiss) private var dismiss
  @State private var isAccepting = false

  var body: some View {
    NavigationStack {
      HPScreenScaffold(widthMode: .compact, maxContentWidth: 520) { _ in
        if let invitation = appState.pendingInvitation {
          HPCard {
            VStack(alignment: .leading, spacing: HP.Space.md) {
              HPWorkspaceHeader(
                "Organization Invitation",
                orgLabel: invitation.organization_name,
                context: invitation.invitation_context.invitedRole
              )
              Text("Confirm that you want to join this organization as \(invitation.invitation_context.invitedRole.lowercased()). The server—not the link URL—controls the organization, role, team, and responsibilities.")
                .font(HP.Font.callout).foregroundStyle(HP.Color.textMuted)
              if let error = appState.invitationErrorText {
                HPErrorState(title: "Invitation not accepted", message: error)
              }
              HPButton(title: "Accept Invitation", systemImage: "checkmark.shield", variant: .primary, isLoading: isAccepting, fullWidth: true) {
                Task {
                  isAccepting = true
                  await appState.acceptPendingInvitation()
                  isAccepting = false
                  if appState.pendingInvitation == nil { dismiss() }
                }
              }
              HPButton(title: "Sign Out and Use Another Account", systemImage: "person.crop.circle.badge.xmark", variant: .secondary, fullWidth: true) {
                Task { await appState.signOut() }
              }
            }
          }
        }
      }
      .navigationTitle("Invitation")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Not Now") { appState.dismissPendingInvitation(); dismiss() }
        }
      }
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
