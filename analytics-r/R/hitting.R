hp_batted_balls <- function(data) {
  if (!all(c("ExitSpeed", "Angle") %in% names(data))) return(data.frame())
  data[is.finite(data$ExitSpeed) & is.finite(data$Angle), , drop = FALSE]
}

hp_hitting_summary <- function(data) {
  batted <- hp_batted_balls(data)
  terminal <- tryCatch(hp_terminal_pa(data), error = function(e) data.frame())
  woba <- if (nrow(terminal)) hp_woba(terminal) else numeric()
  data.frame(
    pitches = nrow(data),
    plate_appearances = nrow(terminal),
    batted_balls = nrow(batted),
    swing_pct = hp_round(100 * mean(data$.swing, na.rm = TRUE)),
    chase_pct = hp_round(100 * mean(data$.chase, na.rm = TRUE)),
    whiff_pct = hp_round(hp_pct(sum(data$.whiff, na.rm = TRUE), sum(data$.swing, na.rm = TRUE))),
    avg_exit_velocity = hp_round(hp_mean(batted$ExitSpeed)),
    max_exit_velocity = hp_round(if (nrow(batted)) max(batted$ExitSpeed, na.rm = TRUE) else NA),
    avg_launch_angle = hp_round(hp_mean(batted$Angle)),
    woba = hp_round(hp_mean(woba), 3)
  )
}

hp_percentile_from_benchmark <- function(value, benchmark, key, higher_is_better = TRUE) {
  metric <- benchmark[[key]]
  if (is.null(metric) || !is.finite(value)) return(NA_real_)
  cuts <- hp_num(metric$percentile_values)
  percentiles <- hp_num(metric$percentiles)
  valid <- is.finite(cuts) & is.finite(percentiles)
  if (sum(valid) < 2L) return(NA_real_)
  result <- stats::approx(cuts[valid], percentiles[valid], xout = value, rule = 2, ties = "ordered")$y
  if (!higher_is_better) result <- 100 - result
  max(0, min(100, result))
}

hp_weighted_score <- function(values, weights) {
  available <- is.finite(values)
  if (sum(available) < 4L) return(NA_real_)
  sum(values[available] * weights[available]) / sum(weights[available])
}

hp_quality_scores <- function(data, benchmark = list()) {
  batted <- hp_batted_balls(data)
  terminal <- tryCatch(hp_terminal_pa(data), error = function(e) data.frame())
  batted_count <- nrow(batted)
  pa_count <- nrow(terminal)
  swings <- sum(data$.swing, na.rm = TRUE)
  hits <- if (nrow(terminal)) sum(grepl("single|double|triple|homer", hp_lower(terminal$PlayResult)), na.rm = TRUE) else 0
  total_bases <- if (nrow(terminal)) sum(c(0, 1, 2, 3, 4)[match(hp_lower(terminal$PlayResult), c("", "single", "double", "triple", "homerun"))], na.rm = TRUE) else 0
  at_bats <- if (nrow(terminal)) sum(!grepl("walk|hitbypitch|sac", hp_lower(terminal$KorBB)), na.rm = TRUE) else 0
  iso <- if (at_bats > 0) (total_bases / at_bats) - (hits / at_bats) else NA_real_
  observed_woba <- if (nrow(terminal)) hp_mean(hp_woba(terminal)) else NA_real_
  raw <- list(
    expected_contact_value = observed_woba,
    barrel_rate = if (batted_count) 100 * mean(batted$ExitSpeed >= 98 & batted$Angle >= 26 & batted$Angle <= 30, na.rm = TRUE) else NA_real_,
    hard_hit_rate = if (batted_count) 100 * mean(batted$ExitSpeed >= 90, na.rm = TRUE) else NA_real_,
    average_exit_velocity = hp_mean(batted$ExitSpeed),
    iso_contact_damage = iso,
    optimal_launch_angle_rate = if (batted_count) 100 * mean(batted$Angle >= 10 & batted$Angle <= 30, na.rm = TRUE) else NA_real_,
    expected_pa_value = observed_woba,
    walk_rate = if (pa_count) 100 * mean(grepl("walk|bb", hp_lower(terminal$KorBB)), na.rm = TRUE) else NA_real_,
    chase_rate = 100 * mean(data$.chase, na.rm = TRUE),
    whiff_rate = hp_pct(sum(data$.whiff, na.rm = TRUE), swings),
    strikeout_rate = if (pa_count) 100 * mean(grepl("strikeout|k", hp_lower(terminal$KorBB)), na.rm = TRUE) else NA_real_
  )
  qoc_keys <- c("expected_contact_value", "barrel_rate", "hard_hit_rate", "average_exit_velocity", "iso_contact_damage", "optimal_launch_angle_rate")
  qoc_weights <- c(.15, .30, .20, .15, .15, .05)
  qab_keys <- c("expected_pa_value", "walk_rate", "chase_rate", "whiff_rate", "strikeout_rate")
  qab_weights <- c(.05, .20, .25, .25, .25)
  qoc_values <- vapply(qoc_keys, function(key) hp_percentile_from_benchmark(raw[[key]], benchmark, key), numeric(1))
  qab_values <- vapply(qab_keys, function(key) hp_percentile_from_benchmark(raw[[key]], benchmark, key, !key %in% c("chase_rate", "whiff_rate", "strikeout_rate")), numeric(1))
  qoc <- hp_weighted_score(qoc_values, qoc_weights)
  qab <- hp_weighted_score(qab_values, qab_weights)
  grade <- function(score) {
    if (!is.finite(score)) return("Benchmark building")
    if (score >= 80) return("Elite")
    if (score >= 65) return("Strong")
    if (score >= 50) return("Solid")
    if (score >= 35) return("Developing")
    "Needs Work"
  }
  list(
    raw = raw,
    qoc = list(score = hp_null(hp_round(qoc, 0)), grade = grade(qoc), sample = batted_count, provisional = batted_count >= 15 && batted_count < 40, available = batted_count >= 15 && is.finite(qoc)),
    qab = list(score = hp_null(hp_round(qab, 0)), grade = grade(qab), sample = pa_count, pitches = nrow(data), provisional = pa_count >= 20 && pa_count < 50, available = pa_count >= 20 && nrow(data) >= 75 && is.finite(qab))
  )
}

hp_spray_data <- function(data) {
  batted <- hp_batted_balls(data)
  if (!nrow(batted)) return(data.frame())
  direction <- if ("Direction" %in% names(batted)) batted$Direction else if ("Bearing" %in% names(batted)) batted$Bearing else rep(NA_real_, nrow(batted))
  distance <- if ("Distance" %in% names(batted)) batted$Distance else rep(NA_real_, nrow(batted))
  radians <- direction * pi / 180
  data.frame(
    exit_velocity = hp_round(batted$ExitSpeed),
    launch_angle = hp_round(batted$Angle),
    direction = hp_round(direction),
    distance = hp_round(distance),
    x = hp_round(distance * sin(radians), 2),
    y = hp_round(distance * cos(radians), 2),
    result = if ("PlayResult" %in% names(batted)) hp_chr(batted$PlayResult) else "Contact",
    stringsAsFactors = FALSE
  )
}

hp_chase_profile <- function(data) {
  hp_require(data, c("PlateLocSide", "PlateLocHeight", "PitchCall"))
  outside <- data[!data$.in_zone, , drop = FALSE]
  if (!nrow(outside)) return(data.frame())
  outside$direction <- ifelse(outside$PlateLocHeight > HP_ZONE$top, "Up", ifelse(outside$PlateLocHeight < HP_ZONE$bottom, "Down", ifelse(outside$PlateLocSide > HP_ZONE$right, "Right", "Left")))
  directions <- c("Up", "Down", "Left", "Right")
  do.call(rbind, lapply(directions, function(direction) {
    rows <- outside[outside$direction == direction, , drop = FALSE]
    data.frame(direction = direction, pitches = nrow(rows), chase_pct = hp_round(100 * mean(rows$.swing, na.rm = TRUE)))
  }))
}

hp_swing_matrix <- function(data) {
  hp_require(data, c("TaggedPitchType", "Balls", "Strikes", "PitchCall"))
  keys <- unique(data.frame(pitch_type = hp_chr(data$TaggedPitchType), count = data$.count, stringsAsFactors = FALSE))
  do.call(rbind, lapply(seq_len(nrow(keys)), function(index) {
    rows <- data[hp_chr(data$TaggedPitchType) == keys$pitch_type[[index]] & data$.count == keys$count[[index]], , drop = FALSE]
    data.frame(pitch_type = keys$pitch_type[[index]], count = keys$count[[index]], pitches = nrow(rows), swing_pct = hp_round(100 * mean(rows$.swing, na.rm = TRUE)), whiff_pct = hp_round(hp_pct(sum(rows$.whiff, na.rm = TRUE), sum(rows$.swing, na.rm = TRUE))))
  }))
}

hp_approach_by_count <- function(data) {
  hp_require(data, c("Balls", "Strikes", "PitchCall"))
  counts <- unique(data$.count)
  counts <- counts[!is.na(counts)]
  do.call(rbind, lapply(counts, function(count) {
    rows <- data[data$.count == count, , drop = FALSE]
    data.frame(count = count, pitches = nrow(rows), swing_pct = hp_round(100 * mean(rows$.swing, na.rm = TRUE)), chase_pct = hp_round(100 * mean(rows$.chase, na.rm = TRUE)), whiff_pct = hp_round(hp_pct(sum(rows$.whiff, na.rm = TRUE), sum(rows$.swing, na.rm = TRUE))), contact_pct = hp_round(100 - hp_pct(sum(rows$.whiff, na.rm = TRUE), sum(rows$.swing, na.rm = TRUE))))
  }))
}

hp_pitch_type_trust <- function(data) {
  hp_require(data, c("TaggedPitchType", "PitchCall", "PlayResult"))
  hp_group_rows(data, "TaggedPitchType", function(rows, pitch_type) {
    batted <- rows[rows$.bip, , drop = FALSE]
    hits <- sum(grepl("single|double|triple|homer", hp_lower(batted$PlayResult)), na.rm = TRUE)
    data.frame(pitch_type = pitch_type, pitches = nrow(rows), balls_in_play = nrow(batted), hits = hits, trust_index = hp_round(hp_pct(hits, nrow(batted))))
  })
}

hp_velocity_exposure <- function(data) {
  hp_require(data, "RelSpeed")
  data$velocity_band <- cut(data$RelSpeed, breaks = HP_VELO_BANDS, labels = HP_VELO_LABELS, include.lowest = TRUE, right = TRUE)
  bands <- HP_VELO_LABELS
  do.call(rbind, lapply(bands, function(band) {
    rows <- data[!is.na(data$velocity_band) & data$velocity_band == band, , drop = FALSE]
    data.frame(velocity_band = band, pitches = nrow(rows), swing_pct = hp_round(100 * mean(rows$.swing, na.rm = TRUE)), chase_pct = hp_round(100 * mean(rows$.chase, na.rm = TRUE)), whiff_pct = hp_round(hp_pct(sum(rows$.whiff, na.rm = TRUE), sum(rows$.swing, na.rm = TRUE))), avg_velocity = hp_round(hp_mean(rows$RelSpeed)))
  }))
}

hp_zone_maps <- function(data) {
  data <- hp_zone_bins(data)
  data <- data[!is.na(data$.zone_x) & !is.na(data$.zone_y), , drop = FALSE]
  keys <- expand.grid(zone_x = c("Left", "Middle", "Right"), zone_y = c("Bottom", "Middle", "Top"), stringsAsFactors = FALSE)
  do.call(rbind, lapply(seq_len(nrow(keys)), function(index) {
    rows <- data[data$.zone_x == keys$zone_x[[index]] & data$.zone_y == keys$zone_y[[index]], , drop = FALSE]
    batted <- rows[rows$.bip, , drop = FALSE]
    terminal <- tryCatch(hp_terminal_pa(rows), error = function(e) data.frame())
    data.frame(
      zone_x = keys$zone_x[[index]], zone_y = keys$zone_y[[index]], pitches = nrow(rows),
      whiff_pct = hp_round(hp_pct(sum(rows$.whiff, na.rm = TRUE), sum(rows$.swing, na.rm = TRUE))),
      take_pct = hp_round(100 * mean(!rows$.swing, na.rm = TRUE)),
      strikeout_pct = if (nrow(terminal)) hp_round(100 * mean(grepl("strikeout|k", hp_lower(terminal$KorBB)), na.rm = TRUE)) else NA,
      barrel_pct = if (nrow(batted)) hp_round(100 * mean(batted$ExitSpeed >= 98 & batted$Angle >= 26 & batted$Angle <= 30, na.rm = TRUE)) else NA,
      woba = if (nrow(terminal)) hp_round(hp_mean(hp_woba(terminal)), 3) else NA,
      stringsAsFactors = FALSE
    )
  }))
}

hp_two_strike <- function(data) {
  hp_require(data, c("Strikes", "PitchCall"))
  rows <- data[data$Strikes == 2, , drop = FALSE]
  summary <- data.frame(
    pitches = nrow(rows), swings = sum(rows$.swing, na.rm = TRUE), swing_pct = hp_round(100 * mean(rows$.swing, na.rm = TRUE)),
    whiffs = sum(rows$.whiff, na.rm = TRUE), whiff_pct = hp_round(hp_pct(sum(rows$.whiff, na.rm = TRUE), sum(rows$.swing, na.rm = TRUE))),
    chase_pct = hp_round(100 * mean(rows$.chase, na.rm = TRUE)), zone_swing_pct = hp_round(100 * mean(rows$.swing[rows$.in_zone], na.rm = TRUE)),
    contact_pct = hp_round(100 - hp_pct(sum(rows$.whiff, na.rm = TRUE), sum(rows$.swing, na.rm = TRUE)))
  )
  list(summary = summary, spray = hp_spray_data(rows), zone = if (nrow(rows)) hp_zone_maps(rows) else data.frame())
}

hp_hitting_analysis <- function(data, topic, benchmark = list()) {
  summary <- hp_hitting_summary(data)
  switch(topic,
    overview_quality = {
      quality <- hp_quality_scores(data, benchmark)
      list(
        metrics = c(hp_metric("qab", "Quality of At Bat", quality$qab$score, "/100", quality$qab$grade, quality$qab$provisional), hp_metric("qoc", "Quality of Contact", quality$qoc$score, "/100", quality$qoc$grade, quality$qoc$provisional), hp_metric("pitches", "Pitches", summary$pitches), hp_metric("batted_balls", "Batted balls", summary$batted_balls)),
        tables = list(hp_table("hitting_summary", "Hitting Summary", summary), hp_table("quality_components", "Quality Score Components", data.frame(metric = names(quality$raw), value = hp_round(unlist(quality$raw), 3)))),
        charts = list(), warnings = unique(c(if (!quality$qab$available) "Insufficient benchmark or sample data for HP-QAB." else NULL, if (!quality$qoc$available) "Insufficient benchmark or sample data for HP-QOC." else NULL))
      )
    },
    contact_spray = {
      hp_require(data, c("ExitSpeed", "Angle"))
      contact_result <- if ("PlayResult" %in% names(data)) data$PlayResult else rep("Contact", nrow(data))
      list(
        metrics = c(hp_metric("avg_exit_velocity", "Average exit velocity", summary$avg_exit_velocity, "mph"), hp_metric("max_exit_velocity", "Maximum exit velocity", summary$max_exit_velocity, "mph")),
        tables = list(),
        charts = hp_compact(list(
          hp_chart("contact_quality", "Contact Quality", "scatter", data.frame(exit_velocity = data$ExitSpeed, launch_angle = data$Angle, result = contact_result), "launch_angle", "exit_velocity", "result"),
          if (hp_has(data, c("ExitSpeed", "Angle", "Direction"))) hp_chart("spray_chart", "Spray Chart", "spray", hp_spray_data(data), "x", "y", "result")
        ))
      )
    },
    swing_decisions = list(metrics = c(hp_metric("chase_pct", "Chase rate", summary$chase_pct, "%"), hp_metric("whiff_pct", "Whiff rate", summary$whiff_pct, "%")), tables = list(hp_table("swing_matrix", "Swing Decision Matrix", hp_swing_matrix(data))), charts = list(hp_chart("chase_profile", "Chase Profile", "bar", hp_chase_profile(data), "direction", "chase_pct"), hp_chart("swing_matrix", "Swing Decision Matrix", "heatmap", hp_swing_matrix(data), "count", "pitch_type", "swing_pct"))),
    count_approach = list(metrics = c(hp_metric("pitches", "Pitches", nrow(data))), tables = list(hp_table("approach_by_count", "Approach by Count", hp_approach_by_count(data)), hp_table("pitch_type_trust", "Pitch Type Trust", hp_pitch_type_trust(data))), charts = list()),
    velocity_exposure = { exposure <- hp_velocity_exposure(data); list(metrics = c(hp_metric("avg_velocity", "Average pitch velocity", hp_round(hp_mean(data$RelSpeed)), "mph")), tables = list(hp_table("velocity_exposure", "Velocity Exposure", exposure)), charts = list(hp_chart("velocity_exposure", "Velocity Exposure", "bar", exposure, "velocity_band", "pitches"))) },
    zone_maps = {
      zones <- hp_zone_maps(data)
      zones$whiff_barrel_index <- hp_round(zones$barrel_pct - zones$whiff_pct)
      list(
        metrics = c(hp_metric("located_pitches", "Located pitches", sum(zones$pitches))),
        tables = list(hp_table("zone_maps", "Zone Map Values", zones)),
        charts = list(
          hp_chart("zone_whiff", "Whiff Rate", "zone_grid", zones, "zone_x", "zone_y", "whiff_pct"),
          hp_chart("zone_take", "Take Rate", "zone_grid", zones, "zone_x", "zone_y", "take_pct"),
          hp_chart("zone_strikeout", "Strikeout Rate", "zone_grid", zones, "zone_x", "zone_y", "strikeout_pct"),
          hp_chart("zone_barrel", "Barrel Rate", "zone_grid", zones, "zone_x", "zone_y", "barrel_pct"),
          hp_chart("zone_whiff_barrel", "Barrel Minus Whiff", "zone_grid", zones, "zone_x", "zone_y", "whiff_barrel_index"),
          hp_chart("zone_woba", "wOBA", "zone_grid", zones, "zone_x", "zone_y", "woba")
        )
      )
    },
    two_strikes = { result <- hp_two_strike(data); list(metrics = lapply(names(result$summary), function(key) hp_metric(key, gsub("_", " ", key), result$summary[[key]][[1]], if (grepl("pct", key)) "%" else NULL)), tables = list(hp_table("two_strike_summary", "Two Strike Summary", result$summary)), charts = list(hp_chart("two_strike_spray", "Two Strike Spray", "spray", result$spray, "x", "y", "result"), hp_chart("two_strike_zone", "Two Strike Whiff Zone", "zone_grid", result$zone, "zone_x", "zone_y", "whiff_pct"))) },
    stop("unsupported_hitting_topic")
  )
}
