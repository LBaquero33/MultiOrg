import Foundation
import Testing
@testable import HomePlate

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
