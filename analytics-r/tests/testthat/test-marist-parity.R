testthat::test_that("Marist TrackMan reference file runs every model when available", {
  path <- Sys.getenv("HOME_PLATE_MARIST_FIXTURE", "/Volumes/EMTEC C280C/R STUFF/Marist_App/TestTrackMan.csv")
  testthat::skip_if_not(file.exists(path), "Canonical Marist fixture is unavailable")
  source <- read.csv(path, check.names = FALSE)
  pitcher <- source[source$Pitcher == unique(source$Pitcher)[1], , drop = FALSE]
  hitter <- source[source$Batter == unique(source$Batter)[1], , drop = FALSE]
  for (topic in names(hp_catalog()$disciplines$pitching$topics)) testthat::expect_silent(hp_analyze(pitcher, list(discipline = "pitching", module = topic, provider = "trackman")))
  for (topic in names(hp_catalog()$disciplines$hitting$topics)) testthat::expect_silent(hp_analyze(hitter, list(discipline = "hitting", module = topic, provider = "trackman")))
  expected <- aggregate(RelSpeed ~ TaggedPitchType, hp_prepare(pitcher), mean, na.rm = TRUE)
  actual <- hp_pitch_metrics(hp_prepare(pitcher))
  joined <- merge(expected, actual, by.x = "TaggedPitchType", by.y = "pitch_type")
  testthat::expect_equal(joined$RelSpeed, joined$avg_velocity, tolerance = .051)

  direct <- aggregate(cbind(RelSpeed, SpinRate, InducedVertBreak, HorzBreak, Extension, RelHeight, RelSide) ~ TaggedPitchType, hp_prepare(pitcher), mean, na.rm = TRUE)
  parity <- merge(direct, actual, by.x = "TaggedPitchType", by.y = "pitch_type")
  testthat::expect_equal(round(parity$SpinRate), parity$avg_spin, tolerance = 1)
  testthat::expect_equal(round(parity$InducedVertBreak, 1), parity$induced_vertical_break, tolerance = .051)
  testthat::expect_equal(round(parity$HorzBreak, 1), parity$horizontal_break, tolerance = .051)
  testthat::expect_equal(round(parity$Extension, 2), parity$extension, tolerance = .006)
  testthat::expect_equal(round(parity$RelHeight, 2), parity$release_height, tolerance = .006)
  testthat::expect_equal(round(parity$RelSide, 2), parity$release_side, tolerance = .006)
  testthat::expect_equal(sum(actual$pitches), nrow(pitcher))
})
