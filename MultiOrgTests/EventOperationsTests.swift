import Foundation
import SwiftUI
import Testing
import XCTest
@testable import HomePlate
#if canImport(UIKit)
import UIKit
#endif

@Suite("Phase 12C baseball day operations")
struct EventOperationsTests {
  @Test("operation modes statuses and state-aware actions are stable")
  func stateModel() {
    #expect(SDEventOperationType.allCases.map(\.rawValue) == [
      "practice_day", "game_day", "tournament_day", "meeting_day", "travel_day", "general_event_day"
    ])
    #expect(SDEventOperationStatus.allCases.map(\.rawValue) == [
      "not_started", "ready", "in_progress", "paused", "completed", "cancelled"
    ])
    #expect(SDEventAvailabilityStatus.allCases.contains(.leavingEarly))
    #expect(SDEventAttendanceStatus.allCases.contains(.partial))
  }

  @Test("availability and attendance remain separate decoded facts")
  func participantFacts() throws {
    let json = """
      {
        "id":"11111111-1111-4111-8111-111111111111",
        "event_operation_id":"22222222-2222-4222-8222-222222222222",
        "user_id":"33333333-3333-4333-8333-333333333333",
        "participant_type":"player",
        "expected":true,
        "availability_status":"unavailable",
        "availability_reason":"family schedule",
        "attendance_status":"present",
        "version":4
      }
      """
    let participant = try JSONDecoder().decode(
      SDEventOperationParticipant.self,
      from: Data(json.utf8)
    )
    #expect(participant.availability_status == .unavailable)
    #expect(participant.attendance_status == .present)
    #expect(participant.availability_reason == "family schedule")
  }

  @Test("Coach Today handles zero one and multiple canonical missions")
  func coachTodaySource() throws {
    let source = try sourceFile("MultiOrg/Features/Coach/CoachTeamCommandCenterView.swift")
    #expect(source.contains("No event today"))
    #expect(source.contains("SDTodayMissionOrdering.ordered"))
    #expect(source.contains("service.today"))
    #expect(source.contains("Today’s Operations"))
    #expect(source.contains("Retry unavailable sections"))
    let model = try sourceFile("MultiOrg/Core/TeamOperationsModels.swift")
    #expect(model.contains("Review Availability"))
    #expect(model.contains("Start Game Day"))
    #expect(model.contains("Start Practice"))
    #expect(model.contains("Start Check-In"))
  }

  @Test("day workspace covers practice game tournament and completion without scorekeeping")
  func workspaceSource() throws {
    let source = try sourceFile("MultiOrg/Features/Coach/CoachEventOperationView.swift")
    for section in ["Mission readiness", "Participants", "Checklist", "Notes", "Event details", "Completion"] {
      #expect(source.contains(section))
    }
    #expect(source.contains("Practice Planner, stations, drills, and live scorekeeping are not part"))
    #expect(source.contains("Tournament:"))
    #expect(source.contains("Mark All Present"))
    #expect(source.contains("Finalize Attendance"))
    #expect(source.contains("Retry Pending Change"))
    #expect(source.contains("Reopen"))
  }

  @Test("consumer Today experiences expose missions and availability but not staff controls")
  func consumerTodaySource() throws {
    let player = try sourceFile("MultiOrg/Features/Player/SDPlayerTodayView.swift")
    let parent = try sourceFile("MultiOrg/Features/Home/ParentHomeView.swift")
    #expect(player.contains("Baseball mission"))
    #expect(player.contains("event.team_name"))
    #expect(player.contains("Update Availability"))
    #expect(player.contains("No visible recap has been published"))
    #expect(parent.contains("Household timing conflict"))
    #expect(parent.contains("ForEach(children)"))
    #expect(parent.contains("Parents declare availability; official attendance"))
    #expect(!player.contains("private_notes"))
    #expect(!parent.contains("attendance_notes"))
  }

  @Test("availability editor explains the boundary and preserves timing state")
  func availabilityEditor() throws {
    let source = try sourceFile("MultiOrg/Features/Home/EventAvailabilityEditorSheet.swift")
    #expect(source.contains("Availability is a pre-event declaration"))
    #expect(source.contains("Coaches record official attendance separately"))
    #expect(source.contains("draft.expectedArrival = enabled"))
    #expect(source.contains("draft.expectedDeparture = enabled"))
  }

  @Test("client retries preserve request IDs and bulk versions")
  func retryAndConcurrency() throws {
    let workspace = try sourceFile("MultiOrg/Features/Coach/CoachEventOperationView.swift")
    let service = try sourceFile("MultiOrg/Core/SupabaseService.swift")
    #expect(workspace.contains("The pending change is preserved on this screen with its original retry identifier"))
    #expect(workspace.contains("retryMutation = mutation"))
    #expect(service.contains("expected_version: $0.version"))
    #expect(service.contains("requestId: UUID = UUID()"))
    #expect(service.contains("participants: participants.map"))
  }

  @Test("backend privacy and transaction boundaries are represented in client-facing sources")
  func backendBoundaries() throws {
    let edge = try sourceFile("supabase/functions/event-operations/index.ts")
    let migration = try sourceFile("supabase/migrations/20260717200000_baseball_day_operations.sql")
    #expect(edge.contains("sanitizeParticipantForConsumer"))
    #expect(edge.contains("event.visibility !== \"team\""))
    #expect(edge.contains("invalid_note_visibility"))
    #expect(edge.contains("sd_apply_event_operation_mutation"))
    #expect(migration.contains("request_fingerprint"))
    #expect(migration.contains("for update of participant"))
    #expect(migration.contains("attendance_finalized_at is not null"))
    #expect(migration.contains("player_coach_note' and visibility in ('staff','player')"))
  }

  @Test("organization admin inspection is separate from live coaching")
  func adminControls() throws {
    let source = try sourceFile("MultiOrg/Features/Admin/OrgEventOperationsAdminView.swift")
    #expect(source.contains("Administrative inspection and correction"))
    #expect(source.contains("Apply Audited Correction"))
    #expect(source.contains("Required correction reason"))
    #expect(source.contains("Reopen Operation"))
    #expect(source.contains("Audit history"))
  }

  @Test("Phase 12C adds no permanent navigation tab")
  func noNewTopLevelTab() {
    let inventory = HPAppNavigationInventory.staff(
      playersTitle: "Players",
      facilitiesTitle: "Facilities",
      programsTitle: "Programs",
      facilitiesEnabled: true,
      chatEnabled: true,
      programsEnabled: true,
      canAdministerOrganization: true,
      isPlatformAdmin: false
    )
    #expect(inventory.compactItems.map(\.destination) == [.coachToday, .coachTeam, .coachSchedule])
    #expect(inventory.compactTabCountIncludingDirectory == 4)
  }

  private func sourceFile(_ path: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
  }
}

@Suite("Phase 12D complete Practice Planner")
struct PracticePlanningTests {
  @Test("plan block and execution states decode independently")
  func stateModels() {
    #expect(SDPracticePlanStatus.allCases.map(\.rawValue) == ["draft", "ready", "published", "active", "completed", "archived"])
    #expect(SDPracticeBlockType.allCases.contains(.hitting))
    #expect(SDPracticeBlockType.allCases.contains(.movementPrep))
    #expect(SDPracticeExecutionStatus.allCases == [.pending, .active, .completed, .skipped, .adjusted])
  }

  @Test("validation is authoritative and classified")
  func validationDecode() throws {
    let data = Data("""
      {"blocking_errors":[{"code":"no_blocks"}],"readiness_warnings":[{"code":"plan_longer_than_event","planned_minutes":120,"event_minutes":90}],"notices":[],"total_duration_minutes":120,"event_duration_minutes":90,"valid":false}
      """.utf8)
    let validation = try JSONDecoder().decode(SDPracticePlanValidation.self, from: data)
    #expect(validation.blocking_errors.first?.code == "no_blocks")
    #expect(validation.readiness_warnings.first?.planned_minutes == 120)
    #expect(!validation.valid)
  }

  @Test("service uses one focused API and retry identifiers")
  func serviceContract() throws {
    let source = try sourceFile("MultiOrg/Core/SupabaseService.swift")
    #expect(source.contains("practice-planning"))
    #expect(source.contains("func mutatePracticePlan"))
    #expect(source.contains("func practicePlanHistory"))
    #expect(source.contains("requestId: UUID = UUID()"))
    #expect(source.contains("list_plan_summaries"))
  }

  @Test("Practice Day contains complete planning and execution workflow")
  func coachWorkflow() throws {
    let source = try sourceFile("MultiOrg/Features/Coach/CoachEventOperationView.swift")
    for label in ["Practice Plan", "Build from Template", "Duplicate Prior", "Plan Editor", "Block List and Parallel Stations", "Edit Block", "Edit Station", "Group Manager", "Edit Group", "Player and Coach Assignment", "Player block / station override", "Coach group", "Assign Group to Block", "Equipment Requirements", "Edit Equipment", "Save Current Plan as Template", "Readiness Validation", "Publish this practice plan?", "Active Practice Plan", "Adjust Active Block", "Add Emergency Block", "Completion Review", "Completed Plan History"] {
      #expect(source.contains(label))
    }
    #expect(source.contains("Retry Pending Plan Change"))
    #expect(source.contains("stale data"))
  }

  @Test("Today Team and Schedule expose contextual plan readiness without a tab")
  func productIntegration() throws {
    let today = try sourceFile("MultiOrg/Features/Coach/CoachTeamCommandCenterView.swift")
    let schedule = try sourceFile("MultiOrg/Features/Coach/CoachTeamScheduleView.swift")
    let aggregate = try sourceFile("supabase/functions/today/index.ts")
    #expect(today.contains("service.today"))
    #expect(aggregate.contains("sd_practice_plans"))
    #expect(aggregate.contains("plan_missing"))
    #expect(today.contains("Plan readiness:"))
    #expect(schedule.contains("Open Practice Plan"))
    let inventory = HPAppNavigationInventory.staff(playersTitle: "Players", facilitiesTitle: "Facilities", programsTitle: "Programs", facilitiesEnabled: true, chatEnabled: true, programsEnabled: true, canAdministerOrganization: true, isPlatformAdmin: false)
    #expect(inventory.compactItems.map(\.destination) == [.coachToday, .coachTeam, .coachSchedule])
  }

  @Test("player and parent receive redacted practice summaries")
  func consumerExperience() throws {
    let player = try sourceFile("MultiOrg/Features/Player/SDPlayerTodayView.swift")
    let parent = try sourceFile("MultiOrg/Features/Home/ParentHomeView.swift")
    #expect(player.contains("Your group:"))
    #expect(player.contains("Bring "))
    #expect(parent.contains("’s group:"))
    #expect(!player.contains("practice.coach_notes"))
    #expect(!parent.contains("coaching_points"))
  }

  @Test("organization admin inspects readiness and audited reopen")
  func adminExperience() throws {
    let source = try sourceFile("MultiOrg/Features/Admin/OrgEventOperationsAdminView.swift")
    #expect(source.contains("Practice plan inspection"))
    #expect(source.contains("Reopen Completed Practice Plan"))
    #expect(source.contains("Required practice reopen reason"))
    #expect(source.contains("Rename Template"))
    #expect(source.contains("Duplicate Template"))
  }

  @Test("schema preserves snapshots history audit privacy and isolation")
  func schemaBoundaries() throws {
    let source = try sourceFile("supabase/migrations/20260717220000_complete_practice_planner.sql")
    for token in ["uq_sd_practice_plans_primary_event", "sd_practice_plans_event_scope_fk", "sd_practice_plan_snapshots", "sd_practice_block_executions", "sd_practice_plan_adjustments", "request_fingerprint", "stale_version", "practice_plan_published", "practice_completed"] {
      #expect(source.contains(token))
    }
    #expect(!source.contains("drop table"))
  }

  @Test("capability UI consumes server values rather than responsibility mapping")
  func clientAuthorization() throws {
    let model = try sourceFile("MultiOrg/Core/TeamOperationsModels.swift")
    let workspace = try sourceFile("MultiOrg/Features/Coach/CoachEventOperationView.swift")
    #expect(model.contains("viewPracticePlan"))
    #expect(model.contains("reopenPracticePlan"))
    #expect(workspace.contains("capabilitySet.contains"))
    #expect(!workspace.contains("case \"head_coach\": return"))
  }

  private func sourceFile(_ path: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
  }
}

@Suite("Phase 12E complete Game Operations")
struct GameOperationsTests {
  @Test("travel-ball lineup models have no nine-player ceiling")
  func flexibleLineupModels() throws {
    #expect(SDGameLineupMode.allCases.map(\.rawValue) == [
      "standard_nine", "standard_nine_with_dh", "standard_nine_with_one_eh",
      "standard_nine_with_multiple_eh", "continuous_batting_order",
      "bat_entire_available_roster", "custom"
    ])
    #expect(SDGameOffensiveRole.allCases.contains(.eh))
    #expect(SDGameOffensiveRole.allCases.contains(.dh))
    #expect(SDGameOffensiveRole.allCases.contains(.offensiveOnly))
    #expect(SDGameOffensiveRole.allCases.contains(.courtesyRunner))
    #expect(SDGameOffensiveRole.allCases.contains(.bench))

    let entries = (1...14).map { index in
      """
      {"id":"00000000-0000-4000-8000-\(String(format: "%012d", index))","game_plan_id":"11111111-1111-4111-8111-111111111111","player_id":"22222222-2222-4222-8222-\(String(format: "%012d", index))","batting_slot":\(index),"offensive_role":"\(index > 9 ? "eh" : "hitter")","active":true,"starter":true,"eligible":true,"source":"manual","version":1}
      """
    }.joined(separator: ",")
    let decoded = try JSONDecoder().decode([SDGameBattingEntry].self, from: Data("[\(entries)]".utf8))
    #expect(decoded.count == 14)
    #expect(decoded.filter { $0.offensive_role == .eh }.count == 5)
  }

  @Test("server validation findings remain authoritative classifications")
  func validationDecode() throws {
    let data = Data("""
      {"blocking_errors":[{"code":"duplicate_active_hitter","severity":"blocking_error"}],"readiness_warnings":[{"code":"missing_rule_profile","severity":"readiness_warning"}],"notices":[{"code":"rule_profile_uncertainty","severity":"informational_notice"}],"valid":false,"batting_count":12,"eh_count":3}
      """.utf8)
    let validation = try JSONDecoder().decode(SDGamePlanValidation.self, from: data)
    #expect(validation.blocking_errors.first?.code == "duplicate_active_hitter")
    #expect(validation.readiness_warnings.first?.severity == "readiness_warning")
    #expect(validation.batting_count == 12)
    #expect(validation.eh_count == 3)
    #expect(!validation.valid)
  }

  @Test("one authenticated API exposes retry and version contracts")
  func serviceContract() throws {
    let source = try sourceFile("MultiOrg/Core/SupabaseService.swift")
    #expect(source.contains("game-operations"))
    #expect(source.contains("func gamePlan("))
    #expect(source.contains("func gamePlanHistory"))
    #expect(source.contains("func gamePlanSummaries"))
    #expect(source.contains("func mutateGamePlan"))
    #expect(source.contains("requestId: UUID = UUID()"))
  }

  @Test("Game Day workspace includes every primary planning and completion surface")
  func coachWorkflow() throws {
    let source = try sourceFile("MultiOrg/Features/Coach/CoachEventOperationView.swift")
    for label in [
      "Game Plan", "Rule Profile", "Lineup Mode", "Batting Order", "Add Hitter",
      "Add Extra Hitter", "Add Multiple Extra Hitters", "Bat Entire Roster",
      "Player Eligibility", "Starting Defense", "Defensive Planning",
      "Copy Prior Inning", "Pitcher & Catcher Plan", "Pitcher-catcher pairing",
      "Game Staff Assignments", "Game Readiness", "Publish Game Plan",
      "Started Game Snapshot", "Active Game Adjustment", "Final Result",
      "Post-Game Recap", "Completed Game History"
    ] { #expect(source.contains(label)) }
    #expect(source.contains("Retry Pending Change"))
    #expect(source.contains("stale data"))
    #expect(!source.contains("play-by-play"))
    #expect(!source.contains("pitch-by-pitch"))
  }

  @Test("Today Team Schedule and Admin expose contextual game readiness")
  func roleIntegration() throws {
    let today = try sourceFile("MultiOrg/Features/Coach/CoachTeamCommandCenterView.swift")
    let schedule = try sourceFile("MultiOrg/Features/Coach/CoachTeamScheduleView.swift")
    let admin = try sourceFile("MultiOrg/Features/Admin/OrgEventOperationsAdminView.swift")
    let aggregate = try sourceFile("supabase/functions/today/index.ts")
    #expect(today.contains("service.today"))
    #expect(aggregate.contains("sd_game_plans"))
    #expect(aggregate.contains("lineup_mode"))
    #expect(today.contains("Game readiness:"))
    #expect(today.contains("gamePlanSummaries"))
    #expect(schedule.contains("Open Game Plan"))
    #expect(admin.contains("Game plan inspection"))
    #expect(admin.contains("Reopen Completed Game Plan"))
    let inventory = HPAppNavigationInventory.staff(playersTitle: "Players", facilitiesTitle: "Facilities", programsTitle: "Programs", facilitiesEnabled: true, chatEnabled: true, programsEnabled: true, canAdministerOrganization: true, isPlatformAdmin: false)
    #expect(inventory.compactItems.map(\.destination) == [.coachToday, .coachTeam, .coachSchedule])
  }

  @Test("players and parents see only their assignment summaries")
  func consumerExperience() throws {
    let player = try sourceFile("MultiOrg/Features/Player/SDPlayerTodayView.swift")
    let parent = try sourceFile("MultiOrg/Features/Home/ParentHomeView.swift")
    #expect(player.contains("Your batting assignment:"))
    #expect(player.contains("Starting defense"))
    #expect(parent.contains("Game plan:"))
    #expect(parent.contains("Starting defense"))
    #expect(!player.contains("internal_strategy_notes"))
    #expect(!parent.contains("game.adjustments"))
  }

  @Test("schema links canonical systems and preserves immutable history")
  func schemaBoundaries() throws {
    let source = try sourceFile("supabase/migrations/20260718000000_complete_game_operations.sql")
    for token in [
      "uq_sd_game_plans_primary_event", "sd_game_plans_event_scope_fk",
      "sd_game_plan_eligibility", "sd_game_batting_entries",
      "sd_game_defensive_assignments", "sd_game_pitcher_catcher_plans",
      "sd_game_plan_snapshots", "sd_game_active_adjustments", "sd_game_results",
      "request_fingerprint", "stale_version", "game_plan_published", "game_completed"
    ] { #expect(source.contains(token)) }
    #expect(source.contains("pg_catalog.upper(position_code) not in ('EH','DH')"))
    #expect(!source.contains("batting_slot <= 9"))
    #expect(!source.contains("drop table"))
  }

  @Test("client consumes server capabilities and retains specialty scope")
  func authorization() throws {
    let model = try sourceFile("MultiOrg/Core/TeamOperationsModels.swift")
    let edge = try sourceFile("supabase/functions/game-operations/index.ts")
    let workspace = try sourceFile("MultiOrg/Features/Coach/CoachEventOperationView.swift")
    for capability in ["viewGamePlan", "manageBattingOrder", "manageDefensivePlan", "managePitcherCatcherPlan", "reopenGameOperation"] {
      #expect(model.contains(capability))
    }
    #expect(edge.contains("sd_resolve_team_capabilities"))
    #expect(workspace.contains("detail.capabilities"))
    #expect(workspace.contains("capabilities = Set(detail.capabilities ?? [])"))
  }

  private func sourceFile(_ path: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
  }
}

#if canImport(UIKit)
@MainActor
final class GameOperationsRenderTests: XCTestCase {
  func testEssentialGameOperationStates() throws {
    let states: [GameOperationsRenderHarness.State] = [
      .lineup, .batEntireRoster, .multipleEH, .defense, .active,
      .completed, .readOnly, .player, .parent,
    ]
    for state in states {
      let view = GameOperationsRenderHarness(state: state)
        .frame(width: state == .defense ? 834 : 393)
        .background(HP.Color.bg)
      let host = UIHostingController(rootView: view)
      let width: CGFloat = state == .defense ? 834 : 393
      let fitted = host.sizeThatFits(in: CGSize(width: width, height: 2_000))
      let height = min(max(320, ceil(fitted.height)), 2_000)
      host.view.frame = CGRect(x: 0, y: 0, width: width, height: height)
      host.view.layoutIfNeeded()
      let renderer = UIGraphicsImageRenderer(size: host.view.bounds.size)
      let image = renderer.image { host.view.layer.render(in: $0.cgContext) }
      XCTAssertGreaterThan(image.size.width, 0)
      XCTAssertGreaterThan(image.size.height, 0)
    }
  }
}

private struct GameOperationsRenderHarness: View {
  enum State: String {
    case lineup, batEntireRoster, multipleEH, defense, active, completed, readOnly, player, parent
  }

  let state: State

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: HP.Space.md) {
        HPWorkspaceHeader("Game Operations", orgLabel: "Travel 14U", context: title)
        HPCard {
          HPSectionHeader(title) { HPStatusBadge(text: badge, kind: badgeKind) }
          Text(detail).font(HP.Font.callout).foregroundStyle(HP.Color.textMuted)
        }
        content
      }
      .padding(HP.Space.md)
    }
  }

  @ViewBuilder private var content: some View {
    switch state {
    case .lineup, .multipleEH, .batEntireRoster:
      HPCard {
        HPSectionHeader("Batting Order") {
          HPStatusBadge(text: state == .batEntireRoster ? "Entire roster" : "14 hitters", kind: .success)
        }
        ForEach(1...14, id: \.self) { slot in
          HStack {
            Text("\(slot)").monospacedDigit().frame(width: 24)
            Text("Player \(slot)")
            Spacer()
            if state == .multipleEH, slot > 9 { HPStatusBadge(text: "EH\(slot - 9)", kind: .info) }
          }
        }
      }
    case .defense:
      HPCard {
        HPSectionHeader("Defensive Planning") { HPStatusBadge(text: "Innings 1–7", kind: .info) }
        ForEach(1...7, id: \.self) { inning in
          HStack { Text("Inning \(inning)").frame(width: 90, alignment: .leading); Text("P • C • 1B • 2B • 3B • SS • LF • CF • RF") }
        }
        Text("Batting order and defense remain separate. EH and DH are never defensive positions.")
          .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
      }
    case .active:
      HPCard {
        HPSectionHeader("Started Game Snapshot") { HPStatusBadge(text: "Active", kind: .success) }
        Text("Published version 4 is preserved. Later planning changes require a reason and create an audited adjustment.")
        HPButton(title: "Record Active Adjustment", systemImage: "square.and.pencil", variant: .secondary, size: .md) {}
      }
    case .completed:
      HPCard {
        HPSectionHeader("Completion Review") { HPStatusBadge(text: "Final", kind: .success) }
        Text("Travel 14U 8 – 6 Harbor Hawks").font(HP.Font.headline)
        Text("Completed game history preserves the published, started, and final revisions.")
      }
    case .readOnly:
      HPCard {
        HPSectionHeader("Game Plan") { HPStatusBadge(text: "Read only", kind: .neutral) }
        Text("You can inspect the published plan, but your current team responsibility cannot edit or publish it.")
      }
    case .player:
      assignmentCard(owner: "Your", slot: 5, position: "CF • Innings 1–4")
    case .parent:
      assignmentCard(owner: "Avery’s", slot: 5, position: "CF • Innings 1–4")
    }
  }

  private func assignmentCard(owner: String, slot: Int, position: String) -> some View {
    HPCard {
      HPSectionHeader("\(owner) Game Plan") { HPStatusBadge(text: "Published", kind: .success) }
      LabeledContent("Batting assignment", value: "#\(slot) • EH1")
      LabeledContent("Starting defense", value: position)
      Text("Only this player’s authorized assignment and visible reminders are shown.")
        .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
    }
  }

  private var title: String {
    switch state {
    case .lineup: "Flexible Lineup"
    case .batEntireRoster: "Bat Entire Roster"
    case .multipleEH: "Multiple Extra Hitters"
    case .defense: "Inning-by-Inning Defense"
    case .active: "Game Day"
    case .completed: "Completed Game"
    case .readOnly: "Published Plan"
    case .player: "Player Summary"
    case .parent: "Parent Summary"
    }
  }

  private var badge: String { state == .completed ? "Completed" : state == .active ? "In progress" : "Ready" }
  private var badgeKind: HPStatusKind { state == .completed || state == .active ? .success : .info }
  private var detail: String { "vs. Harbor Hawks • Away • Arrive 5:15 PM • First pitch 6:00 PM" }
}
#endif

@Suite("Phase 12Y complete Today experience")
struct CompleteTodayExperienceTests {
  @Test("mission ordering prefers active arrival next later review and stable completion")
  func missionOrdering() {
    let now = Date(timeIntervalSince1970: 1_000)
    let values = [
      mission(id: "f", start: 100, status: "completed"),
      mission(id: "e", start: 200, status: "completed", requiresReview: true),
      mission(id: "d", start: 1_500),
      mission(id: "c", start: 1_200, isNext: true),
      mission(id: "b", start: 1_100, arrival: 900, end: 1_400),
      mission(id: "a", start: 900, end: 1_100, current: true, operation: "in_progress"),
    ]
    #expect(SDTodayMissionOrdering.ordered(values, now: now).map(\.id) == ["a", "b", "c", "d", "e", "f"])
  }

  @Test("attention ordering is severity due date and stable identifier")
  func attentionOrdering() {
    let items = [
      attention(id: "z", severity: .important, due: 900),
      attention(id: "b", severity: .urgent, due: 800),
      attention(id: "a", severity: .urgent, due: 800),
    ]
    #expect(SDTodayAttentionOrdering.ordered(items).map(\.id) == ["a", "b", "z"])
  }

  @Test("coach primary action is lifecycle and capability aware")
  func primaryAction() {
    let capabilities = Set([
      "view_event_operation", "manage_event_availability", "manage_event_attendance",
      "start_event_operation", "complete_event_operation", "create_practice_plan",
      "edit_practice_plan", "manage_game", "manage_practice", "create_game_plan",
      "manage_batting_order",
    ])
    #expect(SDTodayPrimaryActionResolver.coachAction(eventType: "practice", eventStatus: "scheduled", operationState: "ready", planState: "published", unresolvedAvailability: 0, unresolvedAttendance: 0, capabilities: capabilities)?.label == "Start Practice")
    #expect(SDTodayPrimaryActionResolver.coachAction(eventType: "game", eventStatus: "scheduled", operationState: "ready", planState: "draft", unresolvedAvailability: 0, unresolvedAttendance: 0, capabilities: capabilities)?.label == "Build Lineup")
    #expect(SDTodayPrimaryActionResolver.coachAction(eventType: "game", eventStatus: "completed", operationState: "completed", planState: "completed", unresolvedAvailability: 0, unresolvedAttendance: 2, capabilities: capabilities)?.label == "Resolve Attendance")
    #expect(SDTodayPrimaryActionResolver.coachAction(eventType: "game", eventStatus: "scheduled", operationState: "ready", planState: "published", unresolvedAvailability: 0, unresolvedAttendance: 0, capabilities: ["view_event_operation"]) == nil)
  }

  @Test("section unavailability never authorizes an empty authoritative state")
  func scopedUnavailable() {
    let unavailable = SDTodayServiceState(state: .unavailable, message: "Today’s schedule couldn’t be loaded.", as_of: nil)
    #expect(!unavailable.preservesAuthoritativeEmptyState)
    #expect(SDTodayServiceState.available.preservesAuthoritativeEmptyState)
  }

  @Test("context guard rejects cancellation superseded response and organization switch")
  func contextGuard() {
    let current = UUID()
    #expect(SDAsyncRequestGuard.accepts(responseContext: "org-a:team-a", responseToken: current, activeContext: "org-a:team-a", currentToken: current, taskIsCancelled: false))
    #expect(!SDAsyncRequestGuard.accepts(responseContext: "org-a:team-a", responseToken: UUID(), activeContext: "org-a:team-a", currentToken: current, taskIsCancelled: false))
    #expect(!SDAsyncRequestGuard.accepts(responseContext: "org-a:team-a", responseToken: current, activeContext: "org-b:team-b", currentToken: current, taskIsCancelled: false))
    #expect(!SDAsyncRequestGuard.accepts(responseContext: "org-a:team-a", responseToken: current, activeContext: "org-a:team-a", currentToken: current, taskIsCancelled: true))
  }

  @Test("role navigation and owner Overview remain approved")
  func roleNavigation() {
    let player = HPAppNavigationInventory.player(chatEnabled: true, facilitiesEnabled: true, testingEnabled: true, analysisEnabled: true, facilitiesTitle: "Facilities", testingTitle: "Testing")
    #expect(player.compactItems.map(\.title) == ["Today", "Calendar", "Trends", "Chat"])
    let coach = HPAppNavigationInventory.staff(playersTitle: "Players", facilitiesTitle: "Facilities", programsTitle: "Programs", facilitiesEnabled: true, chatEnabled: true, programsEnabled: true, canAdministerOrganization: false, isPlatformAdmin: false)
    #expect(coach.compactItems.map(\.title) == ["Today", "Team", "Schedule"])
    let owner = HPAppNavigationInventory.owner(facilitiesTitle: "Facilities", programsTitle: "Programs", facilitiesEnabled: true, chatEnabled: true, programsEnabled: true, isPlatformAdmin: false)
    #expect(owner.compactItems.map(\.title) == ["Overview", "Finance", "Chat", "Organization"])
  }

  @Test("test-only fixture catalog covers representative role and outage states")
  func fixtureCatalog() {
    #expect(TodayFixtureCatalog.coach.count == 11)
    #expect(TodayFixtureCatalog.player.count == 8)
    #expect(TodayFixtureCatalog.parent.count == 7)
    #expect(TodayFixtureCatalog.owner.count == 8)
    #expect(TodayFixtureCatalog.coach.allSatisfy { $0.context.role == .coach })
    #expect(TodayFixtureCatalog.player.allSatisfy { $0.context.role == .player })
    #expect(TodayFixtureCatalog.parent.allSatisfy { $0.context.role == .parent })
    #expect(TodayFixtureCatalog.owner.allSatisfy { $0.context.role.isOrganizationAdministrator })
    #expect(TodayFixtureCatalog.coach.contains { $0.service("scheduling").state == .unavailable })
    #expect(TodayFixtureCatalog.player.contains { $0.missions.contains { $0.eh_count == 1 } })
    #expect(TodayFixtureCatalog.parent.contains { Set($0.missions.compactMap(\.child_id)).count == 2 })
    #expect(TodayFixtureCatalog.owner.contains { $0.attention_items.count >= 3 })
  }

  private func mission(
    id: String,
    start: TimeInterval,
    arrival: TimeInterval? = nil,
    end: TimeInterval? = nil,
    status: String = "scheduled",
    current: Bool = false,
    isNext: Bool = false,
    requiresReview: Bool = false,
    operation: String? = "ready"
  ) -> SDTodayMission {
    let iso: (TimeInterval?) -> String? = { value in value.map { Date(timeIntervalSince1970: $0).ISO8601Format() } }
    return SDTodayMission(
      id: id, source_type: "event", source_id: UUID(), mission_type: "practice",
      title: id, subtitle: nil, status: status, start_at: iso(start), arrival_at: iso(arrival),
      end_at: iso(end ?? start + 100), location: "Field", team_id: UUID(), team_name: "14U",
      season_id: UUID(), child_id: nil, child_name: nil, urgency: .informational,
      is_current: current, is_next: isNext, requires_review: requiresReview,
      operation_state: operation, plan_state: "published", availability_unresolved: 0,
      attendance_unresolved: 0, lineup_mode: nil, eh_count: nil, batting_slot: nil,
      offensive_role: nil, defensive_assignment: nil, pitcher_catcher_assignment: nil,
      primary_action: nil, secondary_actions: [], attention_count: 0, deep_link: nil
    )
  }

  private func attention(id: String, severity: SDTodayUrgency, due: TimeInterval) -> SDTodayAttentionItem {
    SDTodayAttentionItem(
      id: id, source_type: "event", source_id: nil, category: "test", severity: severity,
      title: id, detail: nil, due_at: Date(timeIntervalSince1970: due).ISO8601Format(),
      action: nil, deep_link: nil
    )
  }
}

private enum TodayFixtureCatalog {
  static let coach = responses(
    role: .coach,
    states: ["no_team", "one_team_no_event", "practice", "game", "multiple_events", "active_practice", "active_game", "completed_review", "schedule_unavailable", "practice_unavailable", "read_only"]
  )
  static let player = responses(
    role: .player,
    states: ["no_event", "practice", "game_eh", "bat_entire_roster", "multiple_events", "cancelled", "access_required", "service_unavailable"]
  )
  static let parent = responses(
    role: .parent,
    states: ["one_child", "multiple_children", "household_conflict", "missing_requirement", "payment_due", "cancelled", "service_unavailable"]
  )
  static let owner = responses(
    role: .owner,
    states: ["new_organization", "no_active_season", "normal", "registration_attention", "finance_attention", "failed_delivery", "attention_heavy", "partial_outage"]
  )

  static func fixture(role: SDTodayRole, state: String) -> SDTodayResponse {
    responses(role: role, states: [state])[0]
  }

  private static func responses(role: SDTodayRole, states: [String]) -> [SDTodayResponse] {
    states.map { state in
      let organizationId = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
      let teamId = state == "no_team" ? nil : UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
      let firstChild = role == .parent ? UUID(uuidString: "33333333-3333-4333-8333-333333333333")! : nil
      let secondChild = state == "multiple_children" || state == "household_conflict"
        ? UUID(uuidString: "44444444-4444-4444-8444-444444444444")! : nil
      let isUnavailable = state == "schedule_unavailable" || state == "service_unavailable" || state == "partial_outage"
      let hasNoEvent = ["no_team", "one_team_no_event", "no_event", "new_organization", "no_active_season", "access_required"].contains(state)
      let action = SDTodayAction(id: "open-event", label: role.isOrganizationAdministrator ? "Review Today’s Operations" : "Open Mission", route: "event", capability: "view_event_operation")
      var missions: [SDTodayMission] = hasNoEvent ? [] : [mission(state: state, id: "event-1", teamId: teamId, childId: firstChild, action: action)]
      if state == "multiple_events" || secondChild != nil {
        missions.append(mission(state: state, id: "event-2", teamId: teamId, childId: secondChild, action: action, hour: 22))
      }
      let attentionCount = state == "attention_heavy" ? 3 : (["missing_requirement", "payment_due", "registration_attention", "finance_attention", "failed_delivery", "household_conflict"].contains(state) ? 1 : 0)
      let attention = (0..<attentionCount).map { index in
        SDTodayAttentionItem(
          id: "attention-\(index)", source_type: "fixture", source_id: nil,
          category: index == 0 ? "availability" : index == 1 ? "registration" : "communication",
          severity: index == 0 ? .urgent : .important,
          title: index == 0 ? "Availability needs attention" : index == 1 ? "Registration requirement" : "Announcement acknowledgment",
          detail: "Authorized attention for the current context.", due_at: "2026-07-18T16:00:00Z",
          action: nil, deep_link: nil
        )
      }
      let services = [
        "scheduling": SDTodayServiceState(
          state: isUnavailable ? .unavailable : .available,
          message: isUnavailable ? "Today’s schedule couldn’t be loaded." : nil,
          as_of: "2026-07-18T12:00:00Z"
        ),
        "practice_planning": SDTodayServiceState(
          state: state == "practice_unavailable" ? .unavailable : .available,
          message: state == "practice_unavailable" ? "Practice-plan readiness is temporarily unavailable." : nil,
          as_of: "2026-07-18T12:00:00Z"
        ),
      ]
      return SDTodayResponse(
        context: SDTodayContext(
          organization_id: organizationId, organization_name: "Home Plate Academy", role: role,
          season_id: state == "no_active_season" ? nil : UUID(uuidString: "55555555-5555-4555-8555-555555555555"),
          season_name: state == "no_active_season" ? nil : "Summer", team_id: teamId,
          team_name: teamId == nil ? nil : "14U Navy", child_id: firstChild,
          child_name: firstChild == nil ? nil : "Alex", local_date: "2026-07-18",
          timezone: "America/New_York", scope_type: role.isOrganizationAdministrator ? "organization" : role.rawValue,
          context_token: "fixture-\(role.rawValue)-\(state)"
        ),
        missions: missions,
        attention_items: attention,
        summaries: missions.isEmpty ? [] : [SDTodaySummaryItem(category: "events", label: "Today’s events", value: "\(missions.count)", status: "As of noon", as_of: "2026-07-18T12:00:00Z", action: nil)],
        primary_action: missions.first?.primary_action,
        secondary_actions: [], services: services,
        capabilities: role == .coach ? ["view_event_operation"] : [],
        generated_at: "2026-07-18T12:00:00Z", as_of: "2026-07-18T12:00:00Z"
      )
    }
  }

  private static func mission(
    state: String,
    id: String,
    teamId: UUID?,
    childId: UUID?,
    action: SDTodayAction,
    hour: Int = 18
  ) -> SDTodayMission {
    let isGame = state.contains("game") || state == "bat_entire_roster"
    return SDTodayMission(
      id: id, source_type: "event", source_id: UUID(), mission_type: isGame ? "game" : "practice",
      title: isGame ? "Game vs Harbor Hawks" : "Team Practice", subtitle: "Arrive 30 minutes early",
      status: state == "cancelled" ? "cancelled" : state == "completed_review" ? "completed" : "scheduled",
      start_at: "2026-07-18T\(hour):00:00Z", arrival_at: "2026-07-18T\(hour - 1):30:00Z",
      end_at: "2026-07-18T\(hour + 2):00:00Z", location: "Riverside Field", team_id: teamId,
      team_name: "14U Navy", season_id: UUID(uuidString: "55555555-5555-4555-8555-555555555555"),
      child_id: childId, child_name: childId == nil ? nil : (id == "event-1" ? "Alex" : "Jordan"),
      urgency: .informational, is_current: state.hasPrefix("active_"), is_next: !state.hasPrefix("active_"),
      requires_review: state == "completed_review", operation_state: state.hasPrefix("active_") ? "in_progress" : "ready",
      plan_state: "published", availability_unresolved: 0, attendance_unresolved: 0,
      lineup_mode: state == "bat_entire_roster" ? "bat_entire_roster" : nil,
      eh_count: state == "game_eh" ? 1 : nil, batting_slot: state == "game_eh" ? 7 : nil,
      offensive_role: state == "game_eh" ? "eh" : nil, defensive_assignment: nil,
      pitcher_catcher_assignment: nil, primary_action: action, secondary_actions: [],
      attention_count: 0, deep_link: "homeplate://event/\(id)"
    )
  }
}

#if canImport(UIKit)
@MainActor
final class CompleteTodayRenderTests: XCTestCase {
  func testEssentialTodayStatesRender() {
    for state in TodayRenderHarness.State.allCases {
      let view = TodayRenderHarness(state: state).frame(width: state.isMac ? 1_100 : 393).background(HP.Color.bg)
      let host = UIHostingController(rootView: view)
      let width: CGFloat = state.isMac ? 1_100 : 393
      let fitted = host.sizeThatFits(in: CGSize(width: width, height: 2_400))
      host.view.frame = CGRect(x: 0, y: 0, width: width, height: min(max(360, ceil(fitted.height)), 2_400))
      host.view.layoutIfNeeded()
      let image = UIGraphicsImageRenderer(size: host.view.bounds.size).image { host.view.layer.render(in: $0.cgContext) }
      XCTAssertGreaterThan(image.size.width, 0, state.rawValue)
      XCTAssertGreaterThan(image.size.height, 0, state.rawValue)
    }
  }
}

private struct TodayRenderHarness: View {
  enum State: String, CaseIterable {
    case coachPractice, coachGame, coachMultiple, coachPartialOutage
    case playerNoEvent, playerEH
    case parentMultiChild
    case ownerNormal, ownerAttention, ownerNoSeason, ownerPartialOutage
    var isMac: Bool { rawValue.hasPrefix("owner") || self == .coachPartialOutage }
  }
  let state: State

  private var fixture: SDTodayResponse {
    switch state {
    case .coachPractice: TodayFixtureCatalog.fixture(role: .coach, state: "practice")
    case .coachGame: TodayFixtureCatalog.fixture(role: .coach, state: "game")
    case .coachMultiple: TodayFixtureCatalog.fixture(role: .coach, state: "multiple_events")
    case .coachPartialOutage: TodayFixtureCatalog.fixture(role: .coach, state: "schedule_unavailable")
    case .playerNoEvent: TodayFixtureCatalog.fixture(role: .player, state: "no_event")
    case .playerEH: TodayFixtureCatalog.fixture(role: .player, state: "game_eh")
    case .parentMultiChild: TodayFixtureCatalog.fixture(role: .parent, state: "multiple_children")
    case .ownerNormal: TodayFixtureCatalog.fixture(role: .owner, state: "normal")
    case .ownerAttention: TodayFixtureCatalog.fixture(role: .owner, state: "attention_heavy")
    case .ownerNoSeason: TodayFixtureCatalog.fixture(role: .owner, state: "no_active_season")
    case .ownerPartialOutage: TodayFixtureCatalog.fixture(role: .owner, state: "partial_outage")
    }
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: HP.Space.md) {
        HPWorkspaceHeader(title, orgLabel: fixture.context.organization_name, context: context)
        ForEach(fixture.services.keys.sorted(), id: \.self) { name in
          if let service = fixture.services[name], service.state == .unavailable {
            HPCard { Label(service.message ?? "This section is temporarily unavailable.", systemImage: "wifi.exclamationmark").foregroundStyle(HP.Color.warning) }
          }
        }
        if fixture.missions.isEmpty {
          HPCard { HPEmptyState(title: state == .ownerNoSeason ? "No active season" : "No event today", message: state == .ownerNoSeason ? "Create a season to begin organization operations." : "Your program work and next event remain available.", systemImage: "calendar") }
        } else {
          HPCard {
            HPSectionHeader(state.rawValue.hasPrefix("owner") ? "Today’s Operations" : "Current mission") { HPStatusBadge(text: "Ready", kind: .info) }
            ForEach(fixture.missions) { mission in
              Text([mission.title, mission.team_name, mission.offensive_role?.uppercased(), mission.batting_slot.map { "Batting #\($0)" }].compactMap { $0 }.joined(separator: " • "))
            }
            if let action = fixture.primary_action {
              HPButton(title: action.label, systemImage: "arrow.right.circle", variant: .primary, size: .md) {}
            }
          }
        }
        if !fixture.attention_items.isEmpty {
          HPCard {
            HPSectionHeader("Attention") { HPStatusBadge(text: "\(fixture.attention_items.count)", kind: .warning) }
            ForEach(fixture.attention_items) { Text($0.title) }
          }
        }
      }.padding(HP.Space.md)
    }
  }

  private var title: String { state.rawValue.hasPrefix("owner") ? "Overview" : state.rawValue.hasPrefix("parent") ? "Parent Today" : "Today" }
  private var context: String {
    state.rawValue.hasPrefix("parent") ? "\(Set(fixture.missions.compactMap(\.child_id)).count) linked children" :
      state.rawValue.hasPrefix("owner") ? "Organization-wide" :
      [fixture.context.team_name, fixture.context.season_name].compactMap { $0 }.joined(separator: " • ")
  }
}
#endif
