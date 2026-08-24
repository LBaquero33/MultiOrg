options(homeplate.analytics.root = testthat::test_path("..", ".."))
source(testthat::test_path("..", "..", "R", "load.R"), local = .GlobalEnv)

make_trackman_fixture <- function() {
  set.seed(42)
  count <- 180L
  pitch_types <- rep(c("Fastball", "Slider", "ChangeUp"), length.out = count)
  pitch_calls <- rep(c("Ball", "Strike", "Foul", "Whiff", "Out", "Single", "Double", "HomeRun"), length.out = count)
  play_results <- ifelse(tolower(pitch_calls) %in% c("out", "single", "double", "homerun"), pitch_calls, "Undefined")
  data.frame(
    PitchNo = seq_len(count), Date = rep(as.Date("2026-06-01") + 0:5, length.out = count), Time = "12:00:00",
    GameID = rep(1:3, each = 60), Inning = rep(1:6, length.out = count), Top.Bottom = "Top",
    PAofInning = rep(seq_len(30), each = 6), PitchofPA = rep(1:6, 30),
    Pitcher = "Sample Pitcher", PitcherId = "P-1", PitcherThrows = "Right", PitcherTeam = "Plate Team",
    Batter = "Sample Hitter", BatterId = "B-1", BatterSide = "Right", BatterTeam = "Plate Team",
    Balls = rep(c(0, 1, 2, 3), length.out = count), Strikes = rep(c(0, 1, 2), length.out = count),
    TaggedPitchType = pitch_types, PitchCall = pitch_calls, KorBB = ifelse(pitch_calls == "Whiff" & rep(1:6, 30) == 6, "Strikeout", ""), PlayResult = play_results,
    RelSpeed = c(rnorm(60, 78, 2), rnorm(60, 71, 2), rnorm(60, 69, 2)), SpinRate = c(rnorm(60, 2150, 80), rnorm(60, 2300, 90), rnorm(60, 1700, 75)),
    InducedVertBreak = c(rnorm(60, 16, 1), rnorm(60, 4, 1), rnorm(60, 10, 1)), HorzBreak = c(rnorm(60, 8, 1), rnorm(60, -9, 1), rnorm(60, 13, 1)),
    RelHeight = rnorm(count, 5.8, .08), RelSide = rnorm(count, 1.8, .08), Extension = rnorm(count, 6, .15),
    PlateLocHeight = runif(count, 1, 4), PlateLocSide = runif(count, -1.2, 1.2), ZoneSpeed = rnorm(count, 70, 2),
    ExitSpeed = ifelse(play_results == "Undefined", NA, rnorm(count, 82, 8)), Angle = ifelse(play_results == "Undefined", NA, rnorm(count, 15, 12)),
    Direction = ifelse(play_results == "Undefined", NA, runif(count, -40, 40)), Distance = ifelse(play_results == "Undefined", NA, runif(count, 100, 360)),
    PitchTrajectoryXc0 = 0, PitchTrajectoryXc1 = runif(count, -.2, .2), PitchTrajectoryXc2 = runif(count, -.2, .2),
    PitchTrajectoryYc0 = 55, PitchTrajectoryYc1 = -50, PitchTrajectoryYc2 = 0,
    PitchTrajectoryZc0 = 6, PitchTrajectoryZc1 = runif(count, -2, -1), PitchTrajectoryZc2 = runif(count, -1, 0),
    stringsAsFactors = FALSE, check.names = FALSE
  )
}

make_hittrax_fixture <- function() {
  data.frame(
    ExitSpeed = c(72, 76, 81, 84, 88, 79),
    Angle = c(8, 14, 19, 26, 31, 11),
    Direction = c(-22, -8, 0, 11, 27, 4),
    Distance = c(180, 215, 260, 305, 330, 240),
    stringsAsFactors = FALSE
  )
}

make_rapsodo_pitching_fixture <- function() {
  data.frame(
    TaggedPitchType = rep(c("Fastball", "Slider"), each = 20),
    RelSpeed = c(rnorm(20, 74, 1.5), rnorm(20, 68, 1.2)),
    SpinRate = c(rnorm(20, 2100, 60), rnorm(20, 2250, 70)),
    InducedVertBreak = c(rnorm(20, 15, 1), rnorm(20, 5, 1)),
    HorzBreak = c(rnorm(20, 8, 1), rnorm(20, -7, 1)),
    Extension = rnorm(40, 5.8, .15),
    RelHeight = rnorm(40, 5.7, .08),
    RelSide = rnorm(40, 1.7, .08),
    PlateLocHeight = runif(40, 1.2, 3.8),
    PlateLocSide = runif(40, -1, 1),
    stringsAsFactors = FALSE
  )
}
