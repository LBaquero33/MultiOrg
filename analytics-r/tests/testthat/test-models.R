testthat::test_that("catalog exposes every planned topic", {
  catalog <- hp_catalog()
  testthat::expect_setequal(names(catalog$disciplines$pitching$topics), c("overview_arsenal", "velocity_extension", "pitch_break_shape", "release_location", "counts_finish", "pitch_log"))
  testthat::expect_setequal(names(catalog$disciplines$hitting$topics), c("overview_quality", "contact_spray", "swing_decisions", "count_approach", "velocity_exposure", "zone_maps", "two_strikes"))
})

testthat::test_that("every topic model has exactly one availability definition", {
  catalog <- hp_catalog()
  for (discipline in c("pitching", "hitting")) {
    topic_models <- unique(unlist(lapply(catalog$disciplines[[discipline]]$topics, `[[`, "models")))
    definitions <- vapply(catalog$disciplines[[discipline]]$models, `[[`, character(1), "key")
    testthat::expect_setequal(topic_models, definitions)
    testthat::expect_false(anyDuplicated(definitions) > 0)
  }
})

testthat::test_that("all pitching and hitting topics return the shared contract", {
  fixture <- make_trackman_fixture()
  for (topic in names(hp_catalog()$disciplines$pitching$topics)) {
    result <- hp_analyze(fixture, list(discipline = "pitching", module = topic, provider = "trackman"))
    testthat::expect_equal(result$schema_version, 1L)
    testthat::expect_equal(result$module, topic)
    testthat::expect_true(is.list(result$tables))
    testthat::expect_true(is.list(result$charts))
  }
  for (topic in names(hp_catalog()$disciplines$hitting$topics)) {
    result <- hp_analyze(fixture, list(discipline = "hitting", module = topic, provider = "trackman"))
    testthat::expect_equal(result$schema_version, 1L)
    testthat::expect_equal(result$module, topic)
  }
})

testthat::test_that("pitching overview and count topics expose every planned table", {
  fixture <- hp_prepare(make_trackman_fixture())
  overview <- hp_pitching_analysis(fixture, "overview_arsenal")
  counts <- hp_pitching_analysis(fixture, "counts_finish")
  testthat::expect_setequal(
    vapply(overview$tables, `[[`, character(1), "id"),
    c("pitch_metrics", "bauer_grades", "pitch_results", "performance_against")
  )
  testthat::expect_setequal(
    vapply(counts$tables, `[[`, character(1), "id"),
    c("count_performance", "count_usage", "put_away")
  )
})

testthat::test_that("zone analysis returns all requested map variants", {
  result <- hp_hitting_analysis(hp_prepare(make_trackman_fixture()), "zone_maps")
  testthat::expect_setequal(
    vapply(result$charts, `[[`, character(1), "id"),
    c("zone_whiff", "zone_take", "zone_strikeout", "zone_barrel", "zone_whiff_barrel", "zone_woba")
  )
})

testthat::test_that("youth velocity exposure uses the requested bands", {
  exposure <- hp_velocity_exposure(make_trackman_fixture())
  testthat::expect_equal(exposure$velocity_band, HP_VELO_LABELS)
})

testthat::test_that("quality scores do not fabricate missing benchmarks", {
  scores <- hp_quality_scores(hp_prepare(make_trackman_fixture()), list())
  testthat::expect_false(scores$qab$available)
  testthat::expect_false(scores$qoc$available)
  testthat::expect_equal(scores$qab$grade, "Benchmark building")
})

testthat::test_that("HitTrax contact data returns supported charts without TrackMan count fields", {
  result <- hp_analyze(make_hittrax_fixture(), list(discipline = "hitting", module = "contact_spray", provider = "hittrax"))
  testthat::expect_equal(vapply(result$charts, `[[`, character(1), "id"), c("contact_quality", "spray_chart"))
  testthat::expect_true(any(vapply(result$unavailable_reasons, function(item) grepl("Not supported|Missing", item$reason), logical(1))))
  quality <- hp_analyze(make_hittrax_fixture(), list(discipline = "hitting", module = "overview_quality", provider = "hittrax"))
  testthat::expect_true(any(vapply(quality$source_coverage$models, function(item) item$key == "quality_scores" && item$available, logical(1))))
})

testthat::test_that("Rapsodo pitching returns partial topics without trajectory or pitch calls", {
  fixture <- make_rapsodo_pitching_fixture()
  velocity <- hp_analyze(fixture, list(discipline = "pitching", module = "velocity_extension", provider = "rapsodo"))
  shape <- hp_analyze(fixture, list(discipline = "pitching", module = "pitch_break_shape", provider = "rapsodo"))
  location <- hp_analyze(fixture, list(discipline = "pitching", module = "release_location", provider = "rapsodo"))
  testthat::expect_true(length(velocity$charts) >= 1)
  testthat::expect_equal(vapply(shape$charts, `[[`, character(1), "id"), "pitch_shape")
  testthat::expect_setequal(vapply(location$charts, `[[`, character(1), "id"), c("release_clusters", "pitch_location"))
  testthat::expect_length(location$tables, 0)
})

testthat::test_that("cache is bounded by explicit sha256 keys", {
  key <- paste(rep("a", 64), collapse = "")
  hp_cache_set(key, list(ok = TRUE))
  testthat::expect_true(hp_cache_get(key)$ok)
  testthat::expect_true(hp_cache_delete(key))
  testthat::expect_null(hp_cache_get(key))
  testthat::expect_false(hp_cache_delete(key))
  testthat::expect_null(hp_cache_get("unsafe"))
})

testthat::test_that("service HMAC rejects replay, expiry, and body tampering", {
  previous <- Sys.getenv("HOME_PLATE_ANALYTICS_HMAC_SECRET", unset = NA_character_)
  on.exit({
    if (is.na(previous)) Sys.unsetenv("HOME_PLATE_ANALYTICS_HMAC_SECRET") else Sys.setenv(HOME_PLATE_ANALYTICS_HMAC_SECRET = previous)
  }, add = TRUE)
  Sys.setenv(HOME_PLATE_ANALYTICS_HMAC_SECRET = "test-service-secret")
  rm(list = ls(.hp_seen_nonces, all.names = TRUE), envir = .hp_seen_nonces)
  make_request <- function(body, timestamp, nonce) {
    body_hash <- digest::digest(body, algo = "sha256", serialize = FALSE)
    signature <- digest::hmac(
      "test-service-secret",
      paste(timestamp, nonce, body_hash, sep = "."),
      algo = "sha256",
      serialize = FALSE
    )
    list(
      HTTP_X_HOME_PLATE_TIMESTAMP = timestamp,
      HTTP_X_HOME_PLATE_NONCE = nonce,
      HTTP_X_HOME_PLATE_SIGNATURE = signature
    )
  }
  body <- '{"module":"velocity_extension"}'
  timestamp <- as.character(floor(as.numeric(Sys.time())))
  request <- make_request(body, timestamp, "nonce_for_testing_123")
  testthat::expect_true(hp_verify_service_request(request, body))
  testthat::expect_false(hp_verify_service_request(request, body))
  tampered <- make_request(body, timestamp, "nonce_for_testing_456")
  testthat::expect_false(hp_verify_service_request(tampered, paste0(body, " ")))
  expired_timestamp <- as.character(as.integer(timestamp) - 121L)
  expired <- make_request(body, expired_timestamp, "nonce_for_testing_789")
  testthat::expect_false(hp_verify_service_request(expired, body))
})

testthat::test_that("benchmark publication thresholds protect small cohorts", {
  fixture <- make_trackman_fixture()
  fixture$athlete_id <- rep(paste0("athlete-", 1:5), length.out = nrow(fixture))
  benchmark <- hp_build_benchmark(fixture, "pitching", "13-14", "athlete_id")
  testthat::expect_equal(benchmark$status, "building")
  testthat::expect_length(benchmark$metrics, 0)
  testthat::expect_false("athlete_id" %in% names(benchmark))
})

testthat::test_that("published benchmarks contain aggregates but no identities", {
  fixture <- make_trackman_fixture()
  fixture <- fixture[rep(seq_len(nrow(fixture)), 12), , drop = FALSE]
  fixture$athlete_id <- rep(paste0("athlete-", seq_len(30)), length.out = nrow(fixture))
  benchmark <- hp_build_benchmark(fixture, "pitching", "15-16", "athlete_id")
  testthat::expect_equal(benchmark$status, "published")
  testthat::expect_true(length(benchmark$metrics) > 0)
  serialized <- jsonlite::toJSON(benchmark, auto_unbox = TRUE)
  testthat::expect_false(grepl("athlete-", serialized, fixed = TRUE))
})

testthat::test_that("published hitting benchmarks include QAB and QOC components", {
  fixture <- make_trackman_fixture()
  fixture <- fixture[rep(seq_len(nrow(fixture)), 6), , drop = FALSE]
  fixture$athlete_id <- rep(paste0("hitter-", seq_len(30)), length.out = nrow(fixture))
  benchmark <- hp_build_benchmark(fixture, "hitting", "15-16", "athlete_id")
  testthat::expect_equal(benchmark$status, "published")
  testthat::expect_true(all(c("walk_rate", "chase_rate", "whiff_rate", "strikeout_rate", "barrel_rate", "hard_hit_rate") %in% names(benchmark$metrics)))
  testthat::expect_false(grepl("hitter-", jsonlite::toJSON(benchmark, auto_unbox = TRUE), fixed = TRUE))
})
