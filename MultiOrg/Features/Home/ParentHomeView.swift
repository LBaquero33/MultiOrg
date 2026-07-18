import SwiftUI

/// Parent-facing home:
/// - Accept invites
/// - View linked children (read-only performance data)
/// - Book facilities + request payment on behalf
struct ParentHomeView: View {
  @EnvironmentObject private var appState: AppState
  @Environment(\.scenePhase) private var scenePhase

  @State private var invites: [SDParentInvite] = []
  @State private var links: [SDParentChildLink] = []
  @State private var children: [Profile] = []
  @State private var todayMissions: [ParentTodayMission] = []
  @State private var todayAggregate: SDTodayResponse?
  @State private var todayServiceError: String?
  @State private var loadToken: UUID?
  @State private var publishedContext: String?
  @State private var availabilityEditor: ParentAvailabilityPresentation?
  @State private var pendingAvailability: ParentPendingAvailability?

  @State private var isLoading = false
  @State private var errorText: String?

#if os(macOS)
  private enum SidebarSelection: Hashable {
    case account
    case child(UUID)

    var storageValue: String {
      switch self {
      case .account: return "account"
      case .child(let id): return "child:\(id.uuidString)"
      }
    }

    init?(storageValue: String) {
      let raw = storageValue.trimmingCharacters(in: .whitespacesAndNewlines)
      if raw == "account" { self = .account; return }
      if raw.hasPrefix("child:") {
        let idRaw = String(raw.dropFirst("child:".count))
        if let id = UUID(uuidString: idRaw) {
          self = .child(id)
          return
        }
      }
      return nil
    }
  }

  @SceneStorage("parent.sidebarSelection") private var selectionStorage: String = ""
  @State private var selection: SidebarSelection? = nil
#endif

  var body: some View {
    Group {
#if os(macOS)
      NavigationSplitView {
        childList
          .navigationTitle("Children")
      } detail: {
        switch selection ?? .account {
        case .account:
          ScrollView {
            VStack(spacing: HP.Space.md) {
              parentTodayCard
              RegistrationFamilySummaryCard(audience: .parent, players: children)
              AccountView().environmentObject(appState)
            }
            .padding(HP.Space.md)
          }
        case .child(let id):
          if let child = children.first(where: { $0.id == id }) {
            ParentChildProfileView(child: child)
              .environmentObject(appState)
          } else {
            emptyState
          }
        }
      }
      .task(id: parentContextIdentity) { await reload() }
#else
      NavigationStack {
        HPWorkspaceScreenLayout {
          HPWorkspaceHeader(
            "Parent",
            context: "Linked player profiles"
          )
        } attention: {
          if isLoading {
            HPCard {
              HPLoadingState(text: "Loading linked children…")
            }
          }
        } metrics: {
          HPMetricCard(
            title: "Linked players",
            value: "\(children.count)",
            context: children.count == 1 ? "1 child profile" : "\(children.count) child profiles"
          )
        } supporting: {
          parentTodayCard
          RegistrationFamilySummaryCard(audience: .parent, players: children)
          HPCard {
            VStack(alignment: .leading, spacing: HP.Space.sm) {
              HPSectionHeader("Children") {
                HPStatusBadge(text: "\(children.count)", kind: .neutral)
              }

              if children.isEmpty, !isLoading {
                HPEmptyState(
                  title: "No children linked yet",
                  message: "Accepted parent invitations will appear here.",
                  systemImage: "person.2"
                )
              } else {
                ForEach(children) { child in
                  NavigationLink {
                    ParentChildProfileView(child: child)
                      .environmentObject(appState)
                  } label: {
                    HStack(spacing: HP.Space.sm) {
                      DHDAvatarView(
                        url: {
                          guard let path = child.avatar_path else { return nil }
                          return appState.supabase?.publicAvatarURL(path: path)
                        }(),
                        initials: String(child.displayName.prefix(2)).uppercased(),
                        size: 36
                      )
                      VStack(alignment: .leading, spacing: 2) {
                        Text(child.displayName)
                          .font(HP.Font.headline)
                          .foregroundStyle(HP.Color.text)
                          .fixedSize(horizontal: false, vertical: true)
                        Text(child.shortId)
                          .font(HP.Font.caption)
                          .foregroundStyle(HP.Color.textMuted)
                      }
                      .frame(maxWidth: .infinity, alignment: .leading)
                      Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(HP.Color.textMuted)
                        .accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                  }
                  .buttonStyle(.plain)

                  if child.id != children.last?.id {
                    Divider().overlay(HP.Color.border.opacity(0.5))
                  }
                }
              }
            }
          }
        }
        .navigationTitle("Parent")
        .toolbar {
          ToolbarItem(placement: .topBarTrailing) {
            Menu {
              Button {
                Task { await reload() }
              } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
              }
              Button(role: .destructive) {
                Task { await appState.signOut() }
              } label: {
                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
              }
            } label: {
              Image(systemName: "ellipsis.circle")
            }
          }
        }
        .task(id: parentContextIdentity) { await reload() }
      }
#endif
    }
    .sheet(
      isPresented: Binding(
        get: { !invites.isEmpty },
        set: { isPresented in
          if !isPresented { invites = [] }
        }
      )
    ) {
      ParentInviteAcceptanceSheet(invites: $invites, onAccept: { inviteId in
        Task { await accept(inviteId: inviteId) }
      })
      .environmentObject(appState)
    }
    .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { _ in errorText = nil })) {
      Button("OK", role: .cancel) {}
    } message: { Text(errorText ?? "") }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { Task { await reload() } }
    }
    .sheet(item: $availabilityEditor) { presentation in
      EventAvailabilityEditorSheet(playerName: presentation.child.displayName, initial: presentation.draft) { draft, requestId in
        availabilityEditor = nil
        saveAvailability(presentation: presentation, draft: draft, requestId: requestId)
      }
    }
  }

  private var parentTodayCard: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Today’s Baseball Missions") {
          HPStatusBadge(text: "\(todayMissions.count)", kind: todayMissions.isEmpty ? .neutral : .info)
        }
        if let todayServiceError {
          HPErrorState(title: "Family attention is unavailable", message: todayServiceError, onRetry: { Task { await reload() } })
        } else if let aggregate = todayAggregate {
          ForEach(aggregate.attention_items) { item in
            Label(item.title, systemImage: item.severity == .urgent ? "exclamationmark.triangle.fill" : "exclamationmark.circle")
              .font(HP.Font.caption.weight(.semibold))
              .foregroundStyle(item.severity == .urgent ? HP.Color.danger : HP.Color.warning)
          }
          ForEach(aggregate.services.keys.sorted(), id: \.self) { name in
            if let state = aggregate.services[name], ![.available, .unauthorized].contains(state.state) {
              Label(state.message ?? "This section is temporarily unavailable.", systemImage: "wifi.exclamationmark")
                .font(HP.Font.caption).foregroundStyle(HP.Color.warning)
            }
          }
        }
        if todayMissions.isEmpty {
          HPEmptyState(title: "No child events today", message: "Visible events for linked children appear here.", systemImage: "calendar")
        } else {
          if hasHouseholdConflict {
            Label("Household timing conflict: linked children have overlapping events.", systemImage: "exclamationmark.triangle")
              .font(HP.Font.caption).foregroundStyle(HP.Color.warning)
          }
          ForEach(children) { child in
            let missions = todayMissions.filter { $0.child.id == child.id }
            if !missions.isEmpty {
              HPSectionHeader(child.displayName) {
                HPStatusBadge(text: "\(missions.count)", kind: .neutral)
              }
              ForEach(missions) { mission in
                VStack(alignment: .leading, spacing: HP.Space.xs) {
                  HStack {
                    Label(mission.event.title, systemImage: mission.event.event_type.systemImage)
                      .font(HP.Font.callout.weight(.semibold)).foregroundStyle(HP.Color.text)
                    Spacer()
                    HPStatusBadge(text: mission.detail.operation?.status.label ?? "Not Started", kind: .info)
                  }
                  Text("Arrive \(mission.event.arrivalDate?.formatted(date: .omitted, time: .shortened) ?? "as scheduled") • Starts \(mission.event.startDate.formatted(date: .omitted, time: .shortened))")
                  if let location = mission.event.location_name?.sdNilIfBlank { Label(location, systemImage: "mappin") }
                  if let attire = mission.event.uniformOrDressCode?.sdNilIfBlank { Label(attire, systemImage: "tshirt") }
                  Text("Availability: \(mission.participant?.availability_status.label ?? "Unknown")")
                    .font(HP.Font.caption.weight(.semibold))
                  if mission.event.status == .cancelled {
                    Label(mission.event.cancellation_reason ?? "Event cancelled", systemImage: "calendar.badge.exclamationmark")
                      .foregroundStyle(HP.Color.warning)
                  } else if mission.event.status == .postponed {
                    Label("Event postponed", systemImage: "clock.badge.exclamationmark")
                      .foregroundStyle(HP.Color.warning)
                  }
                  Button("Update \(child.displayName)’s Availability") {
                    availabilityEditor = ParentAvailabilityPresentation(
                      mission: mission,
                      child: child,
                      draft: availabilityDraft(mission.participant)
                    )
                  }
                  .buttonStyle(.bordered).frame(minHeight: 44)
                  .disabled(
                    mission.detail.operation?.status == .completed ||
                      [.completed, .cancelled, .postponed].contains(mission.event.status)
                  )
                  ForEach(mission.detail.notes ?? []) { note in
                    Text(note.body).font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
                  }
                  if let practice = mission.practicePlan, let plan = practice.plan {
                    Text("Practice: \(plan.title)").font(HP.Font.callout.weight(.semibold))
                    if !plan.objectives.isEmpty { Text(plan.objectives.joined(separator: " • ")) }
                    ForEach(practice.groups) { group in Text("\(mission.child.displayName)’s group: \(group.name)") }
                    ForEach(practice.equipment.filter { $0.visibility == "player_visible" }) { item in
                      Label("Bring \(item.quantity)× \(item.name)", systemImage: "shippingbox")
                    }
                  }
                  if let game = mission.gamePlan, let plan = game.plan {
                    Text("Game plan: \(plan.status.label) • \(plan.lineup_mode.label)").font(HP.Font.callout.weight(.semibold))
                    ForEach(game.batting_order ?? []) { entry in
                      Text("\(mission.child.displayName): batting \(entry.batting_slot.map { "#\($0)" } ?? "bench") • \(entry.offensive_role.label)")
                    }
                    ForEach(game.defense ?? []) { assignment in
                      Text("\(assignment.inning_number == 0 ? "Starting defense" : "Inning \(assignment.inning_number)"): \(assignment.position_label?.sdNilIfBlank ?? assignment.position_code)")
                    }
                    ForEach(game.pitcher_catcher ?? []) { assignment in
                      Text(assignment.role_type.replacingOccurrences(of: "_", with: " ").capitalized)
                    }
                    if let result = game.result {
                      Text(result.team_score.flatMap { team in result.opponent_score.map { "Final: \(team)–\($0)" } } ?? "Game completed")
                    }
                    ForEach(game.recaps ?? []) { recap in Text(recap.body) }
                  }
                }
                .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
                if mission.id != missions.last?.id { Divider() }
              }
            }
          }
        }
        if let pendingAvailability {
          VStack(alignment: .leading, spacing: HP.Space.xs) {
            Text("One availability update is awaiting confirmation.")
              .font(HP.Font.caption).foregroundStyle(HP.Color.warning)
            Button("Retry Update") {
              saveAvailability(
                presentation: pendingAvailability.presentation,
                draft: pendingAvailability.draft,
                requestId: pendingAvailability.requestId
              )
            }
            .buttonStyle(.bordered)
          }
        }
        Text("Parents declare availability; official attendance and roster control remain with authorized team staff.")
          .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
      }
    }
  }

  private var hasHouseholdConflict: Bool {
    for firstIndex in todayMissions.indices {
      for secondIndex in todayMissions.indices where secondIndex > firstIndex {
        let first = todayMissions[firstIndex]
        let second = todayMissions[secondIndex]
        if first.child.id != second.child.id,
           first.event.startDate < second.event.endDate,
           second.event.startDate < first.event.endDate { return true }
      }
    }
    return false
  }

  private func availabilityDraft(_ participant: SDEventOperationParticipant?) -> SDEventAvailabilityDraft {
    SDEventAvailabilityDraft(
      status: participant?.availability_status ?? .unknown,
      reason: participant?.availability_reason ?? "",
      expectedArrival: SDEventOperationDateParser.date(participant?.expected_arrival_at),
      expectedDeparture: SDEventOperationDateParser.date(participant?.expected_departure_at)
    )
  }

#if os(macOS)
  private var childList: some View {
    List(selection: $selection) {
      if isLoading {
        HStack(spacing: HP.Space.sm) {
          ProgressView()
          Text("Loading…").foregroundStyle(HP.Color.textMuted)
        }
      }
      Section {
        Label("Account", systemImage: "gearshape")
          .tag(SidebarSelection.account)
      }
      ForEach(children) { c in
        Text(c.displayName)
          .tag(SidebarSelection.child(c.id))
      }
    }
    .onChange(of: selection) { _, newValue in
      selectionStorage = newValue?.storageValue ?? ""
    }
    .toolbar {
      ToolbarItemGroup(placement: .automatic) {
        Button {
          Task { await reload() }
        } label: {
          Image(systemName: "arrow.clockwise")
        }
      }
    }
  }

  private var emptyState: some View {
    HPStateScreenLayout { _ in
      HPCard {
        HPEmptyState(
          title: "Select a child",
          message: "Choose a child to view their progress.",
          systemImage: "person.crop.circle"
        )
      }
    }
  }
#endif

  private func reload() async {
    guard let supabase = appState.supabase, let orgId = appState.activeOrgId else { return }
    let context = parentContextIdentity
    if publishedContext != context {
      invites = []
      links = []
      children = []
      todayMissions = []
      todayAggregate = nil
    }
    let token = UUID()
    loadToken = token
    isLoading = true
    todayServiceError = nil
    do {
      async let loadedInvites = supabase.listMyParentInvites()
      async let loadedLinks = supabase.listMyParentChildLinks(orgId: orgId)
      let (newInvites, newLinks) = try await (loadedInvites, loadedLinks)
      let ids = newLinks.map(\.child_id)
      let profiles = try await supabase.listProfiles(ids: ids)
      guard acceptsParent(context: context, token: token) else { return }
      invites = newInvites
      links = newLinks
      // Only show player children.
      children = profiles.filter(\.isPlayer).sorted { $0.displayName < $1.displayName }
      do {
        let aggregate = try await supabase.today(
          organizationId: orgId,
          seasonId: appState.selectedSeason?.id,
          teamId: nil,
          contextToken: context
        )
        guard aggregate.context.organization_id == orgId,
              aggregate.context.role == .parent else { return }
        todayAggregate = aggregate
      } catch {
        guard acceptsParent(context: context, token: token) else { return }
        todayServiceError = SDApplicationErrorClassifier.alertMessage(for: error)
      }
      await reloadTodayMissions(supabase: supabase, organizationId: orgId)
      guard acceptsParent(context: context, token: token) else { return }
      publishedContext = context

#if os(macOS)
      if let parsed = SidebarSelection(storageValue: selectionStorage) {
        selection = parsed
      }
      if case .child(let id) = selection, !children.contains(where: { $0.id == id }) {
        selection = nil
      }
      if selection == nil {
        selection = children.first.map { SidebarSelection.child($0.id) } ?? .account
      }
      selectionStorage = selection?.storageValue ?? ""
#endif
    } catch {
      guard acceptsParent(context: context, token: token) else { return }
      if let presentation = SDApplicationErrorClassifier.presentation(for: error, taskIsCancelled: Task.isCancelled) {
        if presentation.category == .notDeployed || presentation.category == .serviceUnavailable {
          todayServiceError = presentation.message
        } else {
          errorText = presentation.message
        }
      }
    }
    guard acceptsParent(context: context, token: token) else { return }
    isLoading = false
  }

  private var parentContextIdentity: String {
    "\(appState.activeOrgAuthorizationKey):\(appState.selectedSeason?.id.uuidString ?? "none"):\(DateUtils.toISODate(Date())):\(TimeZone.current.identifier)"
  }

  private func acceptsParent(context: String, token: UUID) -> Bool {
    SDAsyncRequestGuard.accepts(
      responseContext: context,
      responseToken: token,
      activeContext: parentContextIdentity,
      currentToken: loadToken,
      taskIsCancelled: Task.isCancelled
    )
  }

  private func reloadTodayMissions(supabase: SupabaseService, organizationId: UUID) async {
    let start = Calendar.current.startOfDay(for: Date())
    let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
    var missions: [ParentTodayMission] = []
    for child in children {
      do {
        let events = try await supabase.listTeamEvents(
          organizationId: organizationId,
          teamId: nil,
          playerId: child.id,
          rangeStart: start,
          rangeEnd: end
        ).filter { $0.status != .draft }
        for event in events {
          let detail: SDEventOperationDetailResponse
          do {
            detail = try await supabase.eventOperation(
              organizationId: organizationId,
              eventId: event.id,
              playerId: child.id
            )
          } catch {
            // Preserve the canonical event mission before an operation has been
            // initialized; availability submission performs idempotent setup.
            detail = SDEventOperationDetailResponse(
              ok: true,
              operation: nil,
              participants: [],
              checklist: [],
              notes: [],
              initialized: nil,
              replayed: nil
            )
          }
          let practicePlan = event.event_type == .practice
            ? try? await supabase.practicePlan(organizationId: organizationId, eventId: event.id, playerId: child.id)
            : nil
          let gamePlan = event.event_type == .game
            ? try? await supabase.gamePlan(organizationId: organizationId, eventId: event.id, playerId: child.id)
            : nil
          missions.append(ParentTodayMission(child: child, event: event, detail: detail, practicePlan: practicePlan, gamePlan: gamePlan))
        }
      } catch {
        // One child failing must not hide another child's verified missions.
      }
    }
    todayMissions = missions.sorted { $0.event.startDate < $1.event.startDate }
  }

  private func saveAvailability(
    presentation: ParentAvailabilityPresentation,
    draft: SDEventAvailabilityDraft,
    requestId: UUID
  ) {
    Task {
      guard let supabase = appState.supabase, let organizationId = appState.activeOrgId else { return }
      do {
        _ = try await supabase.updateEventAvailability(
          organizationId: organizationId,
          eventId: presentation.mission.event.id,
          playerId: presentation.child.id,
          participantVersion: presentation.mission.participant?.version,
          draft: draft,
          requestId: requestId
        )
        pendingAvailability = nil
        await reloadTodayMissions(supabase: supabase, organizationId: organizationId)
      } catch {
        pendingAvailability = ParentPendingAvailability(
          presentation: presentation,
          draft: draft,
          requestId: requestId
        )
        errorText = "Availability was not confirmed. The change remains available to retry."
      }
    }
  }

  private func accept(inviteId: UUID) async {
    guard let supabase = appState.supabase else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      try await supabase.acceptParentInvite(inviteId: inviteId)
      await reload()
    } catch {
      errorText = SDApplicationErrorClassifier.alertMessage(
        for: error,
        taskIsCancelled: Task.isCancelled
      )
    }
  }
}

struct RegistrationFamilySummaryCard: View {
  enum Audience: Equatable { case player, parent }
  let audience: Audience
  let players: [Profile]
  @EnvironmentObject private var appState: AppState
  @State private var offerings: [SDRegistrationOffering] = []
  @State private var applications: [SDRegistrationApplication] = []
  @State private var isLoading = false
  @State private var errorText: String?
  @State private var selectedOffering: SDRegistrationOffering?
  @State private var loadToken: UUID?

  init(audience: Audience, players: [Profile] = []) {
    self.audience = audience
    self.players = players
  }

  var body: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader(audience == .parent ? "Family registration" : "My registration") {
          if isLoading { ProgressView().controlSize(.small) }
          else { HPStatusBadge(text: "\(attentionCount) attention", kind: attentionCount == 0 ? .neutral : .warning) }
        }
        if let errorText {
          Label(errorText, systemImage: "wifi.exclamationmark")
            .font(HP.Font.caption).foregroundStyle(HP.Color.warning)
        } else if offerings.isEmpty && applications.isEmpty && !isLoading {
          HPEmptyState(title: "Nothing open right now", message: "Available registrations and application status will appear here.", systemImage: "person.crop.circle.badge.plus")
        } else {
          ForEach(applications.prefix(3)) { application in
            HStack {
              Label(application.state.replacingOccurrences(of: "_", with: " ").capitalized, systemImage: "doc.text")
              Spacer()
              if let balance = application.balance_cents, balance > 0 {
                Text(SDMoney(minorUnits: balance, currency: "usd").formatted())
                  .font(HP.Font.caption.weight(.semibold)).monospacedDigit()
              }
            }
            .accessibilityElement(children: .combine)
          }
          ForEach(offerings.filter { $0.accepting_submissions == true }.prefix(3)) { offering in
            Button {
              selectedOffering = offering
            } label: {
              HStack {
              VStack(alignment: .leading, spacing: 2) {
                Text(offering.name).font(HP.Font.callout.weight(.semibold))
                Text("Registration open • \(SDMoney(minorUnits: offering.fee_cents, currency: "usd").formatted())")
                  .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
              }
              Spacer()
              Image(systemName: "chevron.right").foregroundStyle(HP.Color.textMuted).accessibilityHidden(true)
              }
            }
            .buttonStyle(.plain)
            .frame(minHeight: 44)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Open registration details")
          }
        }
      }
    }
    .task(id: appState.activeOrgId) { await load() }
    .sheet(item: $selectedOffering) { offering in
      NavigationStack {
        RegistrationDraftSheet(
          offering: offering,
          players: players,
          audience: audience,
          onComplete: {
            selectedOffering = nil
            Task { await load() }
          }
        )
        .environmentObject(appState)
      }
    }
  }

  private var attentionCount: Int {
    applications.filter { ["action_required", "waitlisted"].contains($0.state) || ($0.balance_cents ?? 0) > 0 }.count
  }

  @MainActor private func load() async {
    guard let organizationId = appState.activeOrgId, let service = appState.supabase else { return }
    let token = UUID()
    loadToken = token
    isLoading = true; errorText = nil
    do {
      async let loadedOfferings = service.registrationOfferings(organizationId: organizationId)
      async let loadedApplications = service.registrationApplications(organizationId: organizationId)
      let result = try await (loadedOfferings, loadedApplications)
      guard loadToken == token,
            appState.activeOrgId == organizationId,
            !Task.isCancelled else { return }
      offerings = result.0.offerings
      applications = result.1.applications
    } catch {
      guard loadToken == token,
            appState.activeOrgId == organizationId,
            !Task.isCancelled else { return }
      errorText = SDApplicationErrorClassifier.alertMessage(for: error)
    }
    guard loadToken == token,
          appState.activeOrgId == organizationId,
          !Task.isCancelled else { return }
    isLoading = false
  }
}

private struct RegistrationDraftSheet: View {
  let offering: SDRegistrationOffering
  let players: [Profile]
  let audience: RegistrationFamilySummaryCard.Audience
  let onComplete: () -> Void
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var appState: AppState
  @State private var selectedPlayerId: UUID?
  @State private var jerseyNumber = ""
  @State private var positionPreference = ""
  @State private var isSubmitting = false
  @State private var errorText: String?

  var body: some View {
    Form {
      Section("Offering") {
        LabeledContent("Registration", value: offering.name)
        LabeledContent("Fee", value: SDMoney(minorUnits: offering.fee_cents, currency: "usd").formatted())
        if let description = offering.description?.sdNilIfBlank { Text(description) }
      }
      if audience == .parent {
        Section("Player") {
          Picker("Register", selection: $selectedPlayerId) {
            Text("Select a linked child").tag(UUID?.none)
            ForEach(players) { player in Text(player.displayName).tag(Optional(player.id)) }
          }
        }
      }
      Section("Player preferences") {
        TextField("Jersey number request (optional)", text: $jerseyNumber)
        TextField("Position preference (optional)", text: $positionPreference)
      }
      Section {
        Text("Submitting records your application. Required waivers or forms must be completed before approval; Home Plate does not claim legal enforceability for typed signatures.")
          .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
      }
      if let errorText { Section { Label(errorText, systemImage: "exclamationmark.triangle.fill").foregroundStyle(HP.Color.danger) } }
    }
    .navigationTitle("Registration")
    .toolbar {
      ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(isSubmitting) }
      ToolbarItem(placement: .confirmationAction) { Button("Save & Submit") { Task { await submit() } }.disabled(isSubmitting || (audience == .parent && selectedPlayerId == nil)) }
    }
  }

  @MainActor private func submit() async {
    guard let organizationId = appState.activeOrgId, let service = appState.supabase else { return }
    let contextOrganizationId = organizationId
    let playerId = audience == .player ? appState.myProfile?.id : selectedPlayerId
    isSubmitting = true; errorText = nil
    do {
      let draft = try await service.saveRegistrationDraft(
        organizationId: organizationId,
        offering: offering,
        playerId: playerId,
        jerseyNumber: jerseyNumber,
        positionPreference: positionPreference
      )
      _ = try await service.submitRegistration(organizationId: organizationId, application: draft)
      guard appState.activeOrgId == contextOrganizationId, !Task.isCancelled else { return }
      onComplete(); dismiss()
    } catch {
      guard appState.activeOrgId == contextOrganizationId, !Task.isCancelled else { return }
      errorText = SDApplicationErrorClassifier.alertMessage(for: error)
    }
    isSubmitting = false
  }
}

private struct ParentTodayMission: Identifiable {
  let child: Profile
  let event: SDTeamEvent
  let detail: SDEventOperationDetailResponse
  let practicePlan: SDPracticePlanDetailResponse?
  let gamePlan: SDGamePlanDetailResponse?
  var id: String { "\(child.id.uuidString):\(event.id.uuidString)" }
  var participant: SDEventOperationParticipant? {
    detail.participants?.first(where: { $0.user_id == child.id })
  }
}

private struct ParentAvailabilityPresentation: Identifiable {
  let id = UUID()
  let mission: ParentTodayMission
  let child: Profile
  let draft: SDEventAvailabilityDraft
}

private struct ParentPendingAvailability {
  let presentation: ParentAvailabilityPresentation
  let draft: SDEventAvailabilityDraft
  let requestId: UUID
}

private struct ParentInviteAcceptanceSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Binding var invites: [SDParentInvite]
  let onAccept: (UUID) -> Void

  var body: some View {
    NavigationStack {
      HPListScreenLayout {
        HPWorkspaceHeader(
          "Parent invites",
          context: "You have been invited to view one or more players as a parent/guardian."
        )
      } controls: {
        EmptyView()
      } results: { context in
        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            HPSectionHeader("Invites") {
              HPStatusBadge(text: "\(invites.count)", kind: .neutral)
            }
            ForEach(invites) { invite in
              let layout = context.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: HP.Space.sm))
                : AnyLayout(HStackLayout(alignment: .center, spacing: HP.Space.sm))
              layout {
                VStack(alignment: .leading, spacing: 4) {
                  Text("Player: \(invite.child_id.uuidString.prefix(6).uppercased())")
                    .font(HP.Font.headline)
                    .foregroundStyle(HP.Color.text)
                  if let relationship = invite.relationship,
                     !relationship.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(relationship)
                      .font(HP.Font.caption)
                      .foregroundStyle(HP.Color.textMuted)
                  }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HPButton(
                  title: "Accept",
                  systemImage: "checkmark",
                  variant: .secondary,
                  size: .sm,
                  fullWidth: context.isAccessibilitySize,
                  action: { onAccept(invite.id) }
                )
              }
              .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)

              if invite.id != invites.last?.id {
                Divider().overlay(HP.Color.border.opacity(0.5))
              }
            }
          }
        }
      }
      .navigationTitle("Parent invites")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Close") {
            invites = []
            dismiss()
          }
            #if os(macOS)
            .keyboardShortcut(.cancelAction)
            #endif
        }
      }
    }
  }
}
