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
    #expect(workspace.schema_version == 1)
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
}

private final class PlayerDevelopmentFixtureBundleMarker {}
