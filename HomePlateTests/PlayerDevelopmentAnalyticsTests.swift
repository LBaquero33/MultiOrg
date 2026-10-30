import Foundation
import Testing
@testable import HomePlate

@Suite("Native player development analytics")
struct PlayerDevelopmentAnalyticsTests {
  @Test("decodes the versioned R analytics response used by the mobile app")
  func responseContract() throws {
    let payload = """
    {
      "schema_version": 2,
      "model_version": "homeplate-r-analytics.v3.1.0-combined-sources",
      "benchmark_version": "college-2026",
      "generated_at": "2026-09-07T12:00:00Z",
      "discipline": "hitting",
      "module": "overview_quality",
      "sample_summary": {"rows": 24, "dates": 2, "provider": "rapsodo"},
      "benchmark_summary": {"status": "ready", "cohort": "college"},
      "summary_metrics": [
        {"key": "max_ev", "label": "Max EV", "value": 101.4, "unit": "mph", "guidance": "Top result", "provisional": false}
      ],
      "tables": [
        {"id": "contact", "title": "Contact", "columns": [{"key": "ev", "label": "EV"}], "rows": [{"ev": 101.4}]}
      ],
      "charts": [
        {"id": "ev", "title": "Exit velocity", "type": "bar", "x": "bucket", "y": "value", "data": [{"bucket": "95+", "value": 4}]}
      ],
      "guidance": {"summary": "Impact quality is improving.", "sample_note": "24 batted balls"},
      "warnings": [],
      "unavailable_reasons": [],
      "cache_status": "hit"
    }
    """

    let response = try JSONDecoder().decode(SDPlayerAnalyticsResponse.self, from: Data(payload.utf8))
    #expect(response.sampleSummary.rows == 24)
    #expect(response.summaryMetrics.first?.displayValue == "101.40")
    #expect(response.tables.first?.rows.first?["ev"]?.doubleValue == 101.4)
    #expect(response.charts.first?.data.first?["value"]?.doubleValue == 4)
    #expect(response.cacheStatus == "hit")
  }

  @Test("mobile preserves player context and redirects to the full web analytics experience")
  func mobileWebRedirectContract() throws {
    let view = try sourceFile("HomePlate/Features/Coach/NativePlayerAnalyticsView.swift")
    let service = try sourceFile("HomePlate/Core/SupabaseService.swift")

    #expect(view.contains("https://www.homeplateapps.com/app/analysis"))
    #expect(view.contains("name: athleteId == nil ? \"player\" : \"athlete\""))
    #expect(view.contains("Open R Analysis"))
    #expect(view.contains("Player and organization preserved"))
    #expect(!view.contains("runPlayerAnalytics("))
    #expect(service.contains("func listPlayerAnalyticsSources("))
    #expect(service.contains("func runPlayerAnalytics("))
    #expect(service.contains("\"player-development-analytics\""))
  }

  private func sourceFile(_ path: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
  }
}
