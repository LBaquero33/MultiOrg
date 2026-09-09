import Foundation
import HomePlateScoringCore
import Supabase

struct SDScorekeeperLeaseV2: Decodable, Sendable {
  let state: String
  let control_token: String?
  let lease_expires_at: Date?
  let game_version: Int
  let authority_epoch: Int?
  let schema_version: Int
}

struct SDScoringProfileV2: Sendable {
  let id: UUID
  let full_name: String?
  let avatarURL: URL?
}

private struct SDScoringProfileRowV2: Decodable, Sendable {
  let id: UUID
  let full_name: String?
  let avatar_path: String?
}

private struct SDScoringEventRowV2: Decodable, Sendable {
  let id: UUID
  let game_id: UUID
  let play_id: UUID
  let command_id: UUID
  let authority_epoch: Int
  let sequence: Int
  let occurred_at: Date
  let ruleset_version: Int?
  let payload: SDJSONValue
}

struct SDGameStatSnapshotV2: Decodable, Sendable {
  let game_id: UUID
  let org_id: UUID
  let game_version: Int
  let decision_version: Int
  let batting: [BattingLine]
  let pitching: [PitchingLine]
  let fielding: [FieldingLine]
  let team_totals: [TeamTotals]
  let snapshot_status: String?
  let schema_version: Int?
  let ruleset_version: Int?
  let formula_version: String?
  let constants_version: String?
  let generated_at: Date

  private enum CodingKeys: String, CodingKey {
    case game_id, org_id, game_version, decision_version, batting, pitching, fielding
    case team_totals, snapshot_status, schema_version, ruleset_version
    case formula_version, constants_version, generated_at
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    game_id = try values.decode(UUID.self, forKey: .game_id)
    org_id = try values.decode(UUID.self, forKey: .org_id)
    game_version = try values.decode(Int.self, forKey: .game_version)
    decision_version = try values.decode(Int.self, forKey: .decision_version)
    batting = (try? values.decode(FlexibleStatValues<BattingLine>.self, forKey: .batting).values) ?? []
    pitching = (try? values.decode(FlexibleStatValues<PitchingLine>.self, forKey: .pitching).values) ?? []
    fielding = (try? values.decode(FlexibleStatValues<FieldingLine>.self, forKey: .fielding).values) ?? []
    team_totals = (try? values.decode(FlexibleStatValues<TeamTotals>.self, forKey: .team_totals).values) ?? []
    snapshot_status = try? values.decodeIfPresent(String.self, forKey: .snapshot_status)
    schema_version = try? values.decodeIfPresent(Int.self, forKey: .schema_version)
    ruleset_version = try? values.decodeIfPresent(Int.self, forKey: .ruleset_version)
    formula_version = try? values.decodeIfPresent(String.self, forKey: .formula_version)
    constants_version = try? values.decodeIfPresent(String.self, forKey: .constants_version)
    generated_at = (try? values.decode(Date.self, forKey: .generated_at)) ?? Date()
  }

  func snapshot(game: SDGame) -> StatSnapshot {
    StatSnapshot(
      schemaVersion: String(schema_version ?? 1), gameID: game_id,
      organizationID: org_id,
      seasonID: game.season_id ?? game.id,
      status: SnapshotStatus(rawValue: snapshot_status ?? "provisional") ?? .provisional,
      gameVersion: game_version, decisionVersion: decision_version,
      rulesProfileID: game.ruleset_id ?? game.id,
      rulesVersion: ruleset_version ?? game.ruleset_version ?? 1,
      statEnvironmentID: game.id,
      formulaVersion: formula_version ?? "legacy-v1",
      constantsVersion: constants_version ?? "not-configured",
      generatedAt: generated_at,
      batting: batting, pitching: pitching, fielding: fielding,
      teams: team_totals, validationIssues: []
    )
  }
}

private struct FlexibleStatValues<Value: Decodable>: Decodable {
  let values: [Value]
  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let array = try? container.decode([Value].self) { values = array; return }
    if let object = try? container.decode([String: Value].self) { values = Array(object.values); return }
    values = []
  }
}

extension SupabaseService {
  struct NativeSavedLineup: Decodable {
    let player_id: UUID; let batting_order: Int; let position_code: String
  }
  func nativeSavedLineup(gameID: UUID) async throws -> [NativeSavedLineup] {
    try await client.from("sd_game_lineup_entries").select("player_id,batting_order,position_code")
      .eq("game_id", value: gameID).order("batting_order").execute().value
  }
  func acquireScorekeepingControlV2(
    gameId: UUID, deviceId: UUID, sessionId: String
  ) async throws -> SDScorekeeperLeaseV2 {
    struct Parameters: Encodable {
      let p_game_id: UUID
      let p_device_id: UUID
      let p_authenticated_session_id: String
    }
    return try await client.rpc(
      "sd_acquire_scorekeeping_control_v2",
      params: Parameters(
        p_game_id: gameId,
        p_device_id: deviceId,
        p_authenticated_session_id: sessionId
      )
    ).single().execute().value
  }

  func listScoringEventsV2(gameId: UUID, organizationId: UUID) async throws -> [ScoringEvent] {
    var rows: [SDScoringEventRowV2] = []
    var lastSequence = 0
    while true {
      let page: [SDScoringEventRowV2] = try await client
      .from("sd_game_scoring_events")
      .select("id,game_id,play_id,command_id,authority_epoch,sequence,occurred_at,ruleset_version,payload")
      .eq("game_id", value: gameId)
      .eq("org_id", value: organizationId)
      .eq("schema_version", value: 2)
      .gt("sequence", value: lastSequence)
      .order("sequence", ascending: true)
      .limit(500)
      .execute().value
      guard page.first?.sequence == nil || page.first?.sequence == lastSequence + 1,
            zip(page, page.dropFirst()).allSatisfy({ $1.sequence == $0.sequence + 1 }) else {
        throw SDServiceError(category: .malformedResponse, functionName: "scoring ledger sequence gap", statusCode: nil)
      }
      rows.append(contentsOf: page)
      if page.count < 500 { break }
      lastSequence = page.last!.sequence
    }
    return try rows.map { row in
      ScoringEvent(
        id: row.id,
        gameID: row.game_id,
        playID: row.play_id,
        commandID: row.command_id,
        authorityEpoch: row.authority_epoch,
        sequence: row.sequence,
        occurredAt: row.occurred_at,
        rulesVersion: row.ruleset_version ?? 1,
        payload: try SDScoringPayloadDecoder.decode(row.payload)
      )
    }
  }

  func scoringProfilesV2(userIds: [UUID]) async throws -> [SDScoringProfileV2] {
    guard !userIds.isEmpty else { return [] }
    let rows: [SDScoringProfileRowV2] = try await client.from("profiles")
      .select("id,full_name,avatar_path")
      .in("id", values: userIds)
      .execute().value
    return rows.map { row in
      SDScoringProfileV2(
        id: row.id,
        full_name: row.full_name,
        avatarURL: row.avatar_path.flatMap(publicAvatarURL(path:))
      )
    }
  }

  func gameStatSnapshotsV2(gameIds: [UUID]) async throws -> [SDGameStatSnapshotV2] {
    guard !gameIds.isEmpty else { return [] }
    return try await client.from("sd_game_stat_snapshots")
      .select("game_id,org_id,game_version,decision_version,batting,pitching,fielding,team_totals,snapshot_status,schema_version,ruleset_version,formula_version,constants_version,generated_at")
      .in("game_id", values: gameIds)
      .execute().value
  }

  func submitScoringPlayV2(
    envelope: ScoringPlayEnvelopeV2,
    deviceId: UUID,
    controlToken: String
  ) async throws {
    struct Body: Encodable {
      let envelope: ScoringPlayEnvelopeV2
      let deviceID: UUID
      let controlToken: String
    }
    struct Response: Decodable { let ok: Bool }
    let session = try await client.auth.session
    client.functions.setAuth(token: session.accessToken)
    let response: Response = try await client.functions.invoke(
      "game-scoring-v2",
      options: FunctionInvokeOptions(body: Body(
        envelope: envelope,
        deviceID: deviceId,
        controlToken: controlToken
      ))
    )
    guard response.ok else { throw SDServiceError(category: .validation, functionName: "game-scoring-v2", statusCode: 422) }
  }
}

private enum SDScoringPayloadDecoder {
  static func decode(_ value: SDJSONValue) throws -> ScoringEventPayload {
    guard case .object(let payload) = value,
          let type = payload["type"]?.stringValue else { throw ContractError.invalidPayload }
    switch type {
    case "game_started": return .gameStarted
    case "pitch":
      return .pitch(PitchEvent(
        offense: try side(payload, "offense"),
        batterID: try uuid(payload, "batterID"),
        pitcherID: try uuid(payload, "pitcherID"),
        result: try enumValue(payload, "result", PitchResult.self),
        isFirstPitch: payload["isFirstPitch"]?.boolValue ?? false
      ))
    case "plate_appearance":
      return .plateAppearance(PlateAppearanceEvent(
        offense: try side(payload, "offense"),
        batterID: try uuid(payload, "batterID"),
        pitcherID: try uuid(payload, "pitcherID"),
        result: try enumValue(payload, "result", PlateAppearanceResult.self),
        contact: optionalEnum(payload, "contact", ContactType.self),
        fielderSequence: array(payload, "fielderSequence").compactMap {
          $0.stringValue.flatMap(DefensivePosition.init(rawValue:))
        },
        runsBattedIn: payload["runsBattedIn"]?.intValue ?? 0,
        errorFielderID: optionalUUID(payload, "errorFielderID"),
        note: payload["note"]?.stringValue ?? ""
      ))
    case "runner":
      guard case .object(let resolution) = payload["resolution"] else { throw ContractError.invalidPayload }
      return .runner(RunnerEvent(
        offense: try side(payload, "offense"),
        resolution: RunnerResolution(
          id: optionalUUID(resolution, "id") ?? UUID(),
          playerID: try uuid(resolution, "playerID"),
          fromBase: optionalBase(resolution, "fromBase"),
          toBase: optionalBase(resolution, "toBase"),
          scored: resolution["scored"]?.boolValue ?? false,
          isOut: resolution["isOut"]?.boolValue ?? false,
          reason: try enumValue(resolution, "reason", RunnerAdvanceReason.self),
          responsiblePitcherID: optionalUUID(resolution, "responsiblePitcherID"),
          earned: resolution["earned"]?.boolValue
        )
      ))
    case "half_inning_ended":
      return .halfInningEnded(
        previousHalf: try enumValue(payload, "half", GameHalf.self),
        previousInning: payload["inning"]?.intValue ?? 1,
        reason: payload["reason"]?.stringValue ?? "Confirmed"
      )
    case "game_ended": return .gameEnded(reason: payload["reason"]?.stringValue ?? "Final")
    case "play_voided": return .playVoided(
      targetPlayID: try uuid(payload, "playID"),
      reason: payload["reason"]?.stringValue ?? "Correction"
    )
    case "play_restored": return .playRestored(targetPlayID: try uuid(payload, "playID"))
    default: throw ContractError.unsupportedPayload(type)
    }
  }

  private static func uuid(_ payload: [String: SDJSONValue], _ key: String) throws -> UUID {
    guard let value = optionalUUID(payload, key) else { throw ContractError.invalidPayload }
    return value
  }
  private static func optionalUUID(_ payload: [String: SDJSONValue], _ key: String) -> UUID? {
    payload[key]?.stringValue.flatMap(UUID.init(uuidString:))
  }
  private static func side(_ payload: [String: SDJSONValue], _ key: String) throws -> TeamSide {
    try enumValue(payload, key, TeamSide.self)
  }
  private static func enumValue<Value: RawRepresentable>(
    _ payload: [String: SDJSONValue], _ key: String, _ type: Value.Type
  ) throws -> Value where Value.RawValue == String {
    guard let raw = payload[key]?.stringValue, let value = Value(rawValue: raw) else {
      throw ContractError.invalidPayload
    }
    return value
  }
  private static func optionalEnum<Value: RawRepresentable>(
    _ payload: [String: SDJSONValue], _ key: String, _ type: Value.Type
  ) -> Value? where Value.RawValue == String {
    payload[key]?.stringValue.flatMap(Value.init(rawValue:))
  }
  private static func array(_ payload: [String: SDJSONValue], _ key: String) -> [SDJSONValue] {
    guard case .array(let values) = payload[key] else { return [] }
    return values
  }
  private static func optionalBase(_ payload: [String: SDJSONValue], _ key: String) -> Base? {
    payload[key]?.intValue.flatMap(Base.init(rawValue:))
  }

  enum ContractError: LocalizedError {
    case invalidPayload
    case unsupportedPayload(String)
    var errorDescription: String? {
      switch self {
      case .invalidPayload: "A scoring event payload was malformed."
      case .unsupportedPayload(let type): "Scoring event type \(type) is not supported by this app build."
      }
    }
  }
}
