import Foundation

public enum DemoGame {
  public static let seed: GameSeed = {
    let awayNames: [(String, String, String, DefensivePosition)] = [
      ("Cam", "Reynolds", "2", .shortstop),
      ("Parker", "Underwood", "25", .secondBase),
      ("Kai", "Parker", "5", .firstBase),
      ("Cole", "Browning", "8", .centerField),
      ("Jordan", "Issel", "13", .leftField),
      ("Gabe", "Wong", "15", .thirdBase),
      ("Will", "Vivec", "11", .rightField),
      ("Nico", "Masterson", "4", .catcher),
      ("Cruz", "Santos", "55", .pitcher),
    ]
    let homeNames: [(String, String, String, DefensivePosition)] = [
      ("Avery", "Jackson", "51", .shortstop),
      ("Theo", "Smith", "2", .secondBase),
      ("Ty", "Moore", "7", .catcher),
      ("Drew", "Thompson", "25", .firstBase),
      ("Devon", "Baxter", "44", .leftField),
      ("Blake", "Hernandez", "32", .rightField),
      ("Jace", "Roberts", "20", .thirdBase),
      ("Chris", "Yang", "10", .centerField),
      ("Riley", "Howton", "34", .pitcher),
    ]

    func lineup(
      _ rows: [(String, String, String, DefensivePosition)],
      prefix: String,
      photoIndexOffset: Int
    ) -> [LineupEntry] {
      rows.enumerated().map { index, row in
        let id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%@%08d", prefix, index + 1))!
        return LineupEntry(
          player: Player(
            id: id, firstName: row.0, lastName: row.1,
            jerseyNumber: row.2,
            bats: index % 4 == 0 ? .left : .right,
            throwsHand: .right,
            photo: .init(
              bundledAssetName: String(
                format: "hp_headshot_%02d", photoIndexOffset + index + 1
              )
            )
          ),
          battingSlot: index + 1,
          position: row.3
        )
      }
    }

    let away = TeamConfiguration(
      id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
      name: "Hudson Lions", abbreviation: "LIO",
      lineup: lineup(awayNames, prefix: "1000", photoIndexOffset: 0),
      bench: [
        Player(
          id: UUID(uuidString: "00000000-0000-0000-0000-100000000020")!,
          firstName: "Milo", lastName: "Hayes", jerseyNumber: "20",
          photo: .init(bundledAssetName: "hp_headshot_10")
        )
      ]
    )
    let home = TeamConfiguration(
      id: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!,
      name: "Marist Gold", abbreviation: "MGD",
      lineup: lineup(homeNames, prefix: "2000", photoIndexOffset: 10),
      bench: [
        Player(
          id: UUID(uuidString: "00000000-0000-0000-0000-200000000020")!,
          firstName: "Eli", lastName: "Ford", jerseyNumber: "18",
          photo: .init(bundledAssetName: "hp_headshot_20")
        )
      ]
    )
    return GameSeed(
      id: UUID(uuidString: "30000000-0000-0000-0000-000000000001")!,
      organizationID: UUID(uuidString: "40000000-0000-0000-0000-000000000001")!,
      seasonID: UUID(uuidString: "50000000-0000-0000-0000-000000000001")!,
      venue: "McCann Baseball Field",
      home: home,
      away: away
    )
  }()
}
