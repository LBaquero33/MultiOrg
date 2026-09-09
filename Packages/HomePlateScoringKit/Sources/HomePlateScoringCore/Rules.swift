import Foundation

public enum RulesProfileKind: String, Codable, CaseIterable, Sendable {
  case youth
  case nfhs
  case ncaa
  case professional
}

public struct MercyThreshold: Codable, Hashable, Sendable {
  public var afterInning: Int
  public var runDifference: Int

  public init(afterInning: Int, runDifference: Int) {
    self.afterInning = afterInning
    self.runDifference = runDifference
  }
}

public struct GameRulesProfile: Identifiable, Codable, Hashable, Sendable {
  public let id: UUID
  public var kind: RulesProfileKind
  public var name: String
  public var sourceName: String
  public var sourceVersion: String
  public var version: Int
  public var scheduledInnings: Int
  public var outsPerHalf: Int
  public var tiesAllowed: Bool
  public var extraInningsAllowed: Bool
  public var continuousBatting: Bool
  public var designatedHitterAllowed: Bool
  public var extraHitterAllowed: Bool
  public var reentryAllowed: Bool
  public var courtesyRunnerAllowed: Bool
  public var droppedThirdStrike: Bool
  public var stealingAllowed: Bool
  public var leadoffsAllowed: Bool
  public var runCap: Int?
  public var timeLimitMinutes: Int?
  public var noNewInningAfterLimit: Bool
  public var placedRunnerBase: Base?
  public var mercyThresholds: [MercyThreshold]

  public init(
    id: UUID = UUID(), kind: RulesProfileKind, name: String,
    sourceName: String, sourceVersion: String, version: Int = 1,
    scheduledInnings: Int, outsPerHalf: Int = 3,
    tiesAllowed: Bool, extraInningsAllowed: Bool,
    continuousBatting: Bool, designatedHitterAllowed: Bool,
    extraHitterAllowed: Bool, reentryAllowed: Bool,
    courtesyRunnerAllowed: Bool, droppedThirdStrike: Bool,
    stealingAllowed: Bool, leadoffsAllowed: Bool, runCap: Int? = nil,
    timeLimitMinutes: Int? = nil, noNewInningAfterLimit: Bool = false,
    placedRunnerBase: Base? = nil, mercyThresholds: [MercyThreshold] = []
  ) {
    self.id = id
    self.kind = kind
    self.name = name
    self.sourceName = sourceName
    self.sourceVersion = sourceVersion
    self.version = version
    self.scheduledInnings = scheduledInnings
    self.outsPerHalf = outsPerHalf
    self.tiesAllowed = tiesAllowed
    self.extraInningsAllowed = extraInningsAllowed
    self.continuousBatting = continuousBatting
    self.designatedHitterAllowed = designatedHitterAllowed
    self.extraHitterAllowed = extraHitterAllowed
    self.reentryAllowed = reentryAllowed
    self.courtesyRunnerAllowed = courtesyRunnerAllowed
    self.droppedThirdStrike = droppedThirdStrike
    self.stealingAllowed = stealingAllowed
    self.leadoffsAllowed = leadoffsAllowed
    self.runCap = runCap
    self.timeLimitMinutes = timeLimitMinutes
    self.noNewInningAfterLimit = noNewInningAfterLimit
    self.placedRunnerBase = placedRunnerBase
    self.mercyThresholds = mercyThresholds
  }

  public static let youth = GameRulesProfile(
    kind: .youth, name: "Youth / Travel Baseball", sourceName: "Organization profile",
    sourceVersion: "lab-v1", scheduledInnings: 6, tiesAllowed: true,
    extraInningsAllowed: true, continuousBatting: true,
    designatedHitterAllowed: false, extraHitterAllowed: true,
    reentryAllowed: true, courtesyRunnerAllowed: true, droppedThirdStrike: true,
    stealingAllowed: true, leadoffsAllowed: false, runCap: 5,
    timeLimitMinutes: 105, noNewInningAfterLimit: true,
    mercyThresholds: [.init(afterInning: 4, runDifference: 10)]
  )

  public static let nfhs = GameRulesProfile(
    kind: .nfhs, name: "NFHS Baseball", sourceName: "NFHS profile",
    sourceVersion: "lab-v1", scheduledInnings: 7, tiesAllowed: false,
    extraInningsAllowed: true, continuousBatting: false,
    designatedHitterAllowed: true, extraHitterAllowed: false,
    reentryAllowed: true, courtesyRunnerAllowed: true, droppedThirdStrike: true,
    stealingAllowed: true, leadoffsAllowed: true,
    mercyThresholds: [.init(afterInning: 5, runDifference: 10)]
  )

  public static let ncaa = GameRulesProfile(
    kind: .ncaa, name: "NCAA Baseball", sourceName: "NCAA profile",
    sourceVersion: "lab-v1", scheduledInnings: 9, tiesAllowed: false,
    extraInningsAllowed: true, continuousBatting: false,
    designatedHitterAllowed: true, extraHitterAllowed: false,
    reentryAllowed: false, courtesyRunnerAllowed: false, droppedThirdStrike: true,
    stealingAllowed: true, leadoffsAllowed: true
  )

  public static let professional = GameRulesProfile(
    kind: .professional, name: "Professional Baseball", sourceName: "Professional profile",
    sourceVersion: "lab-v1", scheduledInnings: 9, tiesAllowed: false,
    extraInningsAllowed: true, continuousBatting: false,
    designatedHitterAllowed: true, extraHitterAllowed: false,
    reentryAllowed: false, courtesyRunnerAllowed: false, droppedThirdStrike: true,
    stealingAllowed: true, leadoffsAllowed: true, placedRunnerBase: .second
  )
}

public struct StatEnvironment: Identifiable, Codable, Hashable, Sendable {
  public let id: UUID
  public var name: String
  public var formulaVersion: String
  public var constantsVersion: String
  public var walkWeight: Double?
  public var hitByPitchWeight: Double?
  public var singleWeight: Double?
  public var doubleWeight: Double?
  public var tripleWeight: Double?
  public var homeRunWeight: Double?
  public var wOBAScale: Double?
  public var leagueWOBA: Double?
  public var leagueRunsPerPlateAppearance: Double?
  public var fipConstant: Double?
  public var leagueERA: Double?
  public var leagueOBP: Double?
  public var leagueSLG: Double?
  public var leagueFIP: Double?
  public var leagueHRPerFlyBall: Double?
  public var parkFactor: Double?

  public init(
    id: UUID = UUID(), name: String, formulaVersion: String,
    constantsVersion: String, walkWeight: Double?, hitByPitchWeight: Double?,
    singleWeight: Double?, doubleWeight: Double?, tripleWeight: Double?,
    homeRunWeight: Double?, wOBAScale: Double?, leagueWOBA: Double?,
    leagueRunsPerPlateAppearance: Double?, fipConstant: Double?,
    leagueERA: Double?, leagueOBP: Double?, leagueSLG: Double?,
    leagueFIP: Double?, leagueHRPerFlyBall: Double?, parkFactor: Double?
  ) {
    self.id = id
    self.name = name
    self.formulaVersion = formulaVersion
    self.constantsVersion = constantsVersion
    self.walkWeight = walkWeight
    self.hitByPitchWeight = hitByPitchWeight
    self.singleWeight = singleWeight
    self.doubleWeight = doubleWeight
    self.tripleWeight = tripleWeight
    self.homeRunWeight = homeRunWeight
    self.wOBAScale = wOBAScale
    self.leagueWOBA = leagueWOBA
    self.leagueRunsPerPlateAppearance = leagueRunsPerPlateAppearance
    self.fipConstant = fipConstant
    self.leagueERA = leagueERA
    self.leagueOBP = leagueOBP
    self.leagueSLG = leagueSLG
    self.leagueFIP = leagueFIP
    self.leagueHRPerFlyBall = leagueHRPerFlyBall
    self.parkFactor = parkFactor
  }

  public var isCalibrated: Bool {
    [walkWeight, hitByPitchWeight, singleWeight, doubleWeight, tripleWeight,
     homeRunWeight, wOBAScale, leagueWOBA, leagueRunsPerPlateAppearance,
     fipConstant, leagueERA, leagueOBP, leagueSLG, leagueFIP,
     parkFactor].allSatisfy { $0 != nil }
  }

  public static let lab2026 = StatEnvironment(
    name: "2026 Lab Calibration", formulaVersion: "hp-sabermetrics-v1",
    constantsVersion: "demo-2026-v1", walkWeight: 0.69,
    hitByPitchWeight: 0.72, singleWeight: 0.89, doubleWeight: 1.27,
    tripleWeight: 1.62, homeRunWeight: 2.10, wOBAScale: 1.22,
    leagueWOBA: 0.320, leagueRunsPerPlateAppearance: 0.120,
    fipConstant: 3.15, leagueERA: 4.20, leagueOBP: 0.320,
    leagueSLG: 0.410, leagueFIP: 4.15, leagueHRPerFlyBall: 0.115,
    parkFactor: 1.0
  )
}
