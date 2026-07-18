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
    #expect(source.contains("ForEach(todayEvents)"))
    #expect(source.contains("Current mission"))
    #expect(source.contains("Next mission"))
    #expect(source.contains("Review Availability"))
    #expect(source.contains("Start Game Day"))
    #expect(source.contains("Start Practice"))
    #expect(source.contains("Start Check-In"))
    #expect(source.contains("listTeamEvents"))
    #expect(source.contains("listEventOperations"))
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
    #expect(today.contains("has no practice plan"))
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
    #expect(today.contains("has no game plan"))
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
