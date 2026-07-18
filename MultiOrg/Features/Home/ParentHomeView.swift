import SwiftUI

/// Parent-facing home:
/// - Accept invites
/// - View linked children (read-only performance data)
/// - Book facilities + request payment on behalf
struct ParentHomeView: View {
  @EnvironmentObject private var appState: AppState

  @State private var invites: [SDParentInvite] = []
  @State private var links: [SDParentChildLink] = []
  @State private var children: [Profile] = []
  @State private var todayMissions: [ParentTodayMission] = []
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
      .task(id: appState.activeOrgId) { await reload() }
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
        .task(id: appState.activeOrgId) { await reload() }
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
    invites = []
    links = []
    children = []
    guard let supabase = appState.supabase, let orgId = appState.activeOrgId else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      invites = try await supabase.listMyParentInvites()
      links = try await supabase.listMyParentChildLinks(orgId: orgId)
      let ids = links.map(\.child_id)
      let profiles = try await supabase.listProfiles(ids: ids)
      // Only show player children.
      children = profiles.filter(\.isPlayer).sorted { $0.displayName < $1.displayName }
      await reloadTodayMissions(supabase: supabase, organizationId: orgId)

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
      errorText = error.localizedDescription
    }
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
      errorText = error.localizedDescription
    }
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
