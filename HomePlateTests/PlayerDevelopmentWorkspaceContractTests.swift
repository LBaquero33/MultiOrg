import Foundation
import Testing
@testable import HomePlate

@Suite("Player development workspace parity")
struct PlayerDevelopmentWorkspaceContractTests {
  @Test("UI amounts preserve exact integer cents and reject invalid input")
  func readableMoney() {
    #expect(HPOptionalMoneyField.parseCents("19.99") == 1999)
    #expect(HPOptionalMoneyField.parseCents("0") == 0)
    #expect(HPOptionalMoneyField.parseCents(".5") == 50)
    #expect(HPOptionalMoneyField.parseCents("-1") == nil)
    #expect(HPOptionalMoneyField.parseCents("1.001") == nil)
    #expect(HPOptionalMoneyField.parseCents("1,000") == nil)
    #expect(HPOptionalMoneyField.parseCents("999999999999") == nil)
  }

  @Test("Activity presentation formats values without changing source fields")
  func readableActivityFields() {
    let price = SDDevelopmentField(key: "price_cents", label: "Price (cents)", value: "1299", unit: nil)
    #expect(HPReadableValue.field(price) == "$12.99")
    #expect(price.value == "1299")
    #expect(HPReadableValue.words("home_plate") == "Home Plate")
    #expect(HPReadableValue.field(.init(key: "status", label: "Status", value: "checked_in", unit: nil)) == "Checked In")
    #expect(HPReadableValue.uniqueFields([price, price]).count == 1)
    #expect(HPReadableValue.date("not a date") == "not a date")
    #expect(!HPReadableValue.date("2026-09-01T15:00:00+00:00").contains("T15"))
  }

  @Test("Assigned work decodes separately without becoming a submission")
  func plannedWorkRoundTrip() throws {
    let workspace = try fixture()
    var day = try #require(workspace.days.first { $0.status == .missed })
    #expect(day.planned_work == nil)
    day.planned_work = [try #require(workspace.days.flatMap(\.activities).first)]
    let decoded = try JSONDecoder().decode(SDDevelopmentDay.self, from: JSONEncoder().encode(day))
    #expect(decoded.planned_work == day.planned_work)
    #expect(decoded.status == .missed)
    #expect(decoded.activity_count == day.activity_count)
  }

  @Test("Messaging uses the available pane width rather than iPad size class alone")
  func compactIPadMessaging() {
    #expect(!ChatLayoutPolicy.usesSplit(width: 531, isCompact: false, isAccessibility: false))
    #expect(ChatLayoutPolicy.usesSplit(width: 900, isCompact: false, isAccessibility: false))
    #expect(!ChatLayoutPolicy.usesSplit(width: 900, isCompact: true, isAccessibility: false))
    #expect(!ChatLayoutPolicy.usesSplit(width: 900, isCompact: false, isAccessibility: true))
  }

  @Test("Facility R analysis uses athlete identity, not team-player identity")
  func facilityAnalyticsIdentity() throws {
    var player = try fixture().player
    player.subject_type = "facility_athlete"
    let encoded = try JSONEncoder().encode(player)
    let decoded = try JSONDecoder().decode(SDDevelopmentPlayer.self, from: encoded)
    #expect(decoded.analyticsAthleteId == player.id)
    player.subject_type = "team_player"
    #expect(player.analyticsAthleteId == nil)
    player.subject_type = nil
    #expect(player.analyticsAthleteId == nil)
  }

  private func fixture() throws -> SDPlayerDevelopmentWorkspace {
    let bundle = Bundle(for: PlayerDevelopmentFixtureBundleMarker.self)
    let url = try #require(
      bundle.url(forResource: "player_development_workspace", withExtension: "json")
    )
    return try JSONDecoder().decode(
      SDPlayerDevelopmentWorkspace.self,
      from: Data(contentsOf: url)
    )
  }

  @Test("Swift decodes every shared section and source")
  func decodesSharedContract() throws {
    let workspace = try fixture()
    #expect(workspace.schema_version == 2)
    #expect(workspace.player.name == "Parity Player")
    #expect(workspace.sections == [
      "Player Hub",
      "Calendar",
      "Programs",
      "Testing",
      "Sessions & Data",
      "Media",
      "Templates",
      "Testing Setup",
    ])
    #expect(Set(workspace.provider_sessions.map(\.provider)) == ["trackman", "rapsodo"])
    #expect(workspace.days.flatMap(\.activities).contains { $0.source == "hittrax" })
    let squat = try #require(
      workspace.days.flatMap(\.activities).first { $0.title == "Back Squat" }
    )
    #expect(squat.fields?.map(\.label) == ["Sets", "Reps", "Weight", "Velocity"])
    #expect(squat.fields?.first { $0.label == "Weight" }?.unit == "lb")
    #expect(squat.notes == "Moved well")
  }

  @Test("Video-only, missed, and upcoming statuses are authoritative")
  func statusParity() throws {
    let workspace = try fixture()
    let byDate = Dictionary(uniqueKeysWithValues: workspace.days.map { ($0.date, $0) })
    #expect(byDate["2026-08-22"]?.status == .submitted)
    #expect(byDate["2026-08-22"]?.activity_count == 0)
    #expect(byDate["2026-08-22"]?.media_count == 1)
    #expect(byDate["2026-08-20"]?.status == .missed)
    #expect(byDate["2026-08-25"]?.status == .upcoming)
  }

  @Test("Ready media and conversion-required media remain distinct")
  func mediaParity() throws {
    let media = try fixture().days.flatMap(\.media)
    #expect(media.contains { $0.kind == .importFile && $0.playback_status == .ready })
    #expect(media.contains { $0.kind == .sessionVideo && $0.playback_status == .needsConversion })
    #expect(media.contains { $0.kind == .testingFieldVideo })
    #expect(media.contains { $0.kind == .programSetVideo })
  }

  @Test("Workspace requests encode UUIDs in canonical lowercase")
  func requestUUIDNormalization() throws {
    let request = SDPlayerDevelopmentWorkspaceRequest(
      action: "get_workspace",
      org_id: try #require(UUID(uuidString: "800E22AE-2A9D-4109-9E11-1360EEAA8EA7")),
      player_id: try #require(UUID(uuidString: "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE")),
      team_id: try #require(UUID(uuidString: "11111111-2222-4333-8444-555555555555")),
      start_date: "2026-01-01",
      end_date: "2026-12-31",
      media_id: nil
    )
    let object = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
    )
    #expect(object["org_id"] as? String == "800e22ae-2a9d-4109-9e11-1360eeaa8ea7")
    #expect(object["player_id"] as? String == "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee")
    #expect(object["team_id"] as? String == "11111111-2222-4333-8444-555555555555")
  }
}

private final class PlayerDevelopmentFixtureBundleMarker {}
