import Foundation
import Testing
@testable import HomePlate

@Suite("Player development workspace parity")
struct PlayerDevelopmentWorkspaceContractTests {
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

@Suite("WAR operations workspace contract")
struct WAROperationsWorkspaceContractTests {
  @Test("Partial WAR sources remain usable and keep diagnostics")
  func decodesPartialWorkspace() throws {
    let json = """
    {
      "access": {"is_admin": true, "staff_kind": "owner"},
      "athletes": [{"id": "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee", "display_name": "WAR Athlete"}],
      "staff": [],
      "profiles": [],
      "assignments": [],
      "services": [],
      "service_trainers": [],
      "availability": [],
      "availability_exceptions": [],
      "appointments": [],
      "participants": [],
      "outcomes": [],
      "packages": [],
      "ledger": [],
      "testing_templates": [],
      "testing_sessions": [],
      "testing_results": [],
      "locations": [],
      "resources": [],
      "imports": [],
      "site": null,
      "public_profiles": [],
      "source_diagnostics": {"unavailable_sources": ["provider imports"]}
    }
    """

    let workspace = try JSONDecoder().decode(SDWARWorkspace.self, from: Data(json.utf8))
    #expect(workspace.isManager)
    #expect(workspace.athletes.first?.warRecordID == "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee")
    #expect(workspace.athletes.first?.warDisplay("display_name") == "WAR Athlete")
    #expect(workspace.unavailableSources == ["provider imports"])
  }

  @Test("WAR Data Lab response decodes version and source coverage")
  func decodesAnalyticsResponse() throws {
    let json = """
    {
      "schema_version": 1,
      "model_version": "war-performance.v1",
      "benchmark_version": null,
      "discipline": "performance",
      "module": "athlete_overview",
      "sample_summary": {"sessions": 3},
      "source_coverage": {"blast": true, "rapsodo": false},
      "summary_metrics": [{"label": "Bat Speed", "value": 68.4, "unit": "mph"}],
      "tables": [{"id": "sessions", "title": "Sessions", "description": null, "columns": [{"key": "date", "label": "Date"}], "rows": [{"date": "2026-08-27"}]}],
      "charts": [],
      "guidance": {"summary": "Bat speed is trending upward."},
      "warnings": ["Rapsodo data is unavailable."],
      "unavailable_reasons": [{"provider": "rapsodo", "reason": "No source file"}]
    }
    """

    let response = try JSONDecoder().decode(SDWARAnalyticsResponse.self, from: Data(json.utf8))
    #expect(response.model_version == "war-performance.v1")
    #expect(response.module == "athlete_overview")
    #expect(response.sample_summary.warInt("sessions") == 3)
    #expect(response.tables.first?.rows.first?.warString("date") == "2026-08-27")
    #expect(response.unavailable_reasons.first?.warString("provider") == "rapsodo")
  }
}

private final class PlayerDevelopmentFixtureBundleMarker {}
