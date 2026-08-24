hp_group_rows <- function(data, key, summarize) {
  values <- unique(hp_chr(data[[key]]))
  values <- values[nzchar(values) & !is.na(values)]
  if (!length(values)) return(data.frame())
  do.call(rbind, lapply(values, function(value) summarize(data[hp_chr(data[[key]]) == value, , drop = FALSE], value)))
}

hp_pitch_metrics <- function(data) {
  hp_require(data, "TaggedPitchType")
  column_mean <- function(rows, column, digits = 1L) {
    if (!column %in% names(rows)) return(NA_real_)
    hp_round(hp_mean(rows[[column]]), digits)
  }
  total <- nrow(data)
  metrics <- hp_group_rows(data, "TaggedPitchType", function(rows, pitch_type) data.frame(
    pitch_type = pitch_type,
    pitches = nrow(rows),
    usage_pct = hp_round(hp_pct(nrow(rows), total)),
    avg_velocity = column_mean(rows, "RelSpeed"),
    max_velocity = hp_round(if ("RelSpeed" %in% names(rows) && any(is.finite(rows$RelSpeed))) max(rows$RelSpeed, na.rm = TRUE) else NA),
    avg_spin = column_mean(rows, "SpinRate", 0),
    bauer_units = if (hp_has(rows, c("SpinRate", "RelSpeed"))) hp_round(hp_mean(rows$SpinRate / rows$RelSpeed)) else NA_real_,
    induced_vertical_break = column_mean(rows, "InducedVertBreak"),
    horizontal_break = column_mean(rows, "HorzBreak"),
    extension = column_mean(rows, "Extension", 2),
    release_height = column_mean(rows, "RelHeight", 2),
    release_side = column_mean(rows, "RelSide", 2),
    stringsAsFactors = FALSE
  ))
  metrics[order(metrics$usage_pct, decreasing = TRUE), , drop = FALSE]
}

hp_bauer_grades <- function(data) {
  hp_require(data, c("TaggedPitchType", "RelSpeed", "SpinRate"))
  metrics <- hp_pitch_metrics(data)
  raw <- data$SpinRate / data$RelSpeed
  center <- hp_mean(raw)
  spread <- stats::sd(raw, na.rm = TRUE)
  if (!is.finite(spread) || spread == 0) spread <- NA_real_
  metrics$dataset_mean <- hp_round(center)
  metrics$dataset_sd <- hp_round(spread)
  metrics$dataset_z <- hp_round((metrics$bauer_units - center) / spread, 2)
  metrics$grade_20_80 <- hp_round(pmax(20, pmin(80, 50 + 10 * metrics$dataset_z)), 0)
  metrics$index_100 <- hp_round(pmax(50, pmin(150, 100 + 15 * metrics$dataset_z)), 0)
  metrics
}

hp_pitch_results <- function(data) {
  hp_require(data, c("TaggedPitchType", "PitchCall", "PlateLocSide", "PlateLocHeight"))
  total <- nrow(data)
  terminal <- tryCatch(hp_terminal_pa(data), error = function(e) data.frame())
  terminal$woba_value <- hp_woba(terminal)
  hp_group_rows(data, "TaggedPitchType", function(rows, pitch_type) {
    swings <- sum(rows$.swing, na.rm = TRUE)
    matching_terminal <- if (nrow(terminal)) terminal[hp_chr(terminal$TaggedPitchType) == pitch_type, , drop = FALSE] else data.frame()
    data.frame(
      pitch_type = pitch_type,
      pitches = nrow(rows),
      usage_pct = hp_round(hp_pct(nrow(rows), total)),
      zone_pct = hp_round(100 * mean(rows$.in_zone, na.rm = TRUE)),
      chase_pct = hp_round(100 * mean(rows$.chase, na.rm = TRUE)),
      whiff_pct = hp_round(hp_pct(sum(rows$.whiff & rows$.swing, na.rm = TRUE), swings)),
      woba_allowed = hp_round(hp_mean(matching_terminal$woba_value), 3),
      avg_velocity = hp_round(hp_mean(rows$RelSpeed)),
      stringsAsFactors = FALSE
    )
  })
}

hp_performance_against <- function(data) {
  hp_require(data, c("TaggedPitchType", "PitchofPA", "PlayResult"))
  terminal <- hp_terminal_pa(data)
  summarize <- function(rows, pitch_type) {
    result <- hp_lower(rows$PlayResult)
    outcome <- if ("KorBB" %in% names(rows)) hp_lower(rows$KorBB) else rep("", nrow(rows))
    walks <- grepl("walk|bb", outcome)
    hit_by_pitch <- grepl("hitbypitch|hbp", outcome)
    strikeouts <- grepl("strikeout|(^|[^a-z])k([^a-z]|$)", outcome)
    singles <- grepl("single", result)
    doubles <- grepl("double", result)
    triples <- grepl("triple", result)
    home_runs <- grepl("homer|home run", result)
    hits <- singles | doubles | triples | home_runs
    plate_appearances <- nrow(rows)
    at_bats <- max(plate_appearances - sum(walks | hit_by_pitch, na.rm = TRUE), 0)
    total_bases <- sum(singles + 2 * doubles + 3 * triples + 4 * home_runs, na.rm = TRUE)
    obp <- if (plate_appearances) sum(hits | walks | hit_by_pitch, na.rm = TRUE) / plate_appearances else NA_real_
    slg <- if (at_bats) total_bases / at_bats else NA_real_
    contact_rows <- rows[!(walks | hit_by_pitch | strikeouts), , drop = FALSE]
    data.frame(
      pitch_type = pitch_type,
      plate_appearances = plate_appearances,
      walks = sum(walks, na.rm = TRUE),
      strikeouts = sum(strikeouts, na.rm = TRUE),
      batting_average = hp_round(if (at_bats) sum(hits, na.rm = TRUE) / at_bats else NA_real_, 3),
      on_base_percentage = hp_round(obp, 3),
      slugging = hp_round(slg, 3),
      ops = hp_round(obp + slg, 3),
      woba = hp_round(hp_mean(hp_woba(rows)), 3),
      woba_on_contact = hp_round(hp_mean(hp_woba(contact_rows)), 3),
      stringsAsFactors = FALSE
    )
  }
  pitch_rows <- hp_group_rows(terminal, "TaggedPitchType", summarize)
  rbind(summarize(terminal, "All pitches"), pitch_rows)
}

hp_command <- function(data) {
  hp_require(data, c("TaggedPitchType", "PlateLocSide", "PlateLocHeight", "PitchCall"))
  edge_band <- 0.25
  data$.edge <- data$.in_zone & (
    data$PlateLocSide <= HP_ZONE$left + edge_band | data$PlateLocSide >= HP_ZONE$right - edge_band |
      data$PlateLocHeight <= HP_ZONE$bottom + edge_band | data$PlateLocHeight >= HP_ZONE$top - edge_band
  )
  data$.waste <- !data$.in_zone
  hp_group_rows(data, "TaggedPitchType", function(rows, pitch_type) data.frame(
    pitch_type = pitch_type,
    pitches = nrow(rows),
    in_zone_pct = hp_round(100 * mean(rows$.in_zone, na.rm = TRUE)),
    edge_pct = hp_round(100 * mean(rows$.edge, na.rm = TRUE)),
    waste_pct = hp_round(100 * mean(rows$.waste, na.rm = TRUE)),
    chase_pct = hp_round(100 * mean(rows$.chase, na.rm = TRUE)),
    stringsAsFactors = FALSE
  ))
}

hp_put_away <- function(data) {
  hp_require(data, c("TaggedPitchType", "Strikes", "PitchCall"))
  rows <- data[data$Strikes == 2, , drop = FALSE]
  if (!nrow(rows)) return(data.frame())
  hp_group_rows(rows, "TaggedPitchType", function(group, pitch_type) {
    two_strike_pitches <- nrow(group)
    strikeouts <- sum(hp_lower(group$KorBB) %in% c("strikeout", "k"), na.rm = TRUE)
    data.frame(
      pitch_type = pitch_type,
      two_strike_pitches = two_strike_pitches,
      whiff_pct = hp_round(hp_pct(sum(group$.whiff, na.rm = TRUE), sum(group$.swing, na.rm = TRUE))),
      chase_pct = hp_round(100 * mean(group$.chase, na.rm = TRUE)),
      strikeout_events = strikeouts,
      put_away_pct = hp_round(hp_pct(strikeouts, two_strike_pitches)),
      stringsAsFactors = FALSE
    )
  })
}

hp_count_performance <- function(data) {
  hp_require(data, c("Balls", "Strikes", "PitchCall"))
  counts <- unique(data$.count)
  counts <- counts[!is.na(counts)]
  do.call(rbind, lapply(counts, function(count) {
    rows <- data[data$.count == count, , drop = FALSE]
    data.frame(
      count = count,
      pitches = nrow(rows),
      zone_pct = hp_round(100 * mean(rows$.in_zone, na.rm = TRUE)),
      swing_pct = hp_round(100 * mean(rows$.swing, na.rm = TRUE)),
      chase_pct = hp_round(100 * mean(rows$.chase, na.rm = TRUE)),
      whiff_pct = hp_round(hp_pct(sum(rows$.whiff, na.rm = TRUE), sum(rows$.swing, na.rm = TRUE))),
      stringsAsFactors = FALSE
    )
  }))
}

hp_count_usage <- function(data) {
  hp_require(data, c("TaggedPitchType", "Balls", "Strikes"))
  keys <- unique(data.frame(
    count = data$.count,
    pitch_type = hp_chr(data$TaggedPitchType),
    stringsAsFactors = FALSE
  ))
  keys <- keys[!is.na(keys$count) & nzchar(keys$pitch_type), , drop = FALSE]
  do.call(rbind, lapply(seq_len(nrow(keys)), function(index) {
    count <- keys$count[[index]]
    pitch_type <- keys$pitch_type[[index]]
    count_rows <- data[data$.count == count, , drop = FALSE]
    selected <- count_rows[hp_chr(count_rows$TaggedPitchType) == pitch_type, , drop = FALSE]
    data.frame(
      count = count,
      pitch_type = pitch_type,
      pitches = nrow(selected),
      usage_pct = hp_round(hp_pct(nrow(selected), nrow(count_rows))),
      stringsAsFactors = FALSE
    )
  }))
}

hp_pitch_distribution <- function(data, column, group = "TaggedPitchType", bins = 18L) {
  hp_require(data, c(group, column))
  values <- hp_num(data[[column]])
  finite <- values[is.finite(values)]
  if (length(finite) < 2L) return(data.frame())
  breaks <- pretty(range(finite), n = bins)
  groups <- unique(hp_chr(data[[group]]))
  do.call(rbind, lapply(groups, function(label) {
    selected <- values[hp_chr(data[[group]]) == label & is.finite(values)]
    if (!length(selected)) return(NULL)
    hist <- hist(selected, breaks = breaks, plot = FALSE)
    data.frame(pitch_type = label, value = hist$mids, density = hp_round(hist$density, 4), count = hist$counts)
  }))
}

hp_trajectory_3d <- function(data, limit = 120L) {
  coefficients <- c("PitchTrajectoryXc0", "PitchTrajectoryXc1", "PitchTrajectoryXc2", "PitchTrajectoryYc0", "PitchTrajectoryYc1", "PitchTrajectoryYc2", "PitchTrajectoryZc0", "PitchTrajectoryZc1", "PitchTrajectoryZc2")
  hp_require(data, c("TaggedPitchType", coefficients))
  rows <- data[stats::complete.cases(data[coefficients]), , drop = FALSE]
  if (nrow(rows) > limit) rows <- rows[round(seq(1, nrow(rows), length.out = limit)), , drop = FALSE]
  times <- seq(0, 1, length.out = 24)
  output <- list()
  for (index in seq_len(nrow(rows))) {
    row <- rows[index, , drop = FALSE]
    polynomial <- function(prefix) hp_num(row[[paste0(prefix, "0")]]) + hp_num(row[[paste0(prefix, "1")]]) * times + hp_num(row[[paste0(prefix, "2")]]) * times^2
    output[[length(output) + 1L]] <- list(
      pitch_type = hp_chr(row$TaggedPitchType),
      points = lapply(seq_along(times), function(i) list(x = polynomial("PitchTrajectoryXc")[[i]], y = polynomial("PitchTrajectoryYc")[[i]], z = polynomial("PitchTrajectoryZc")[[i]]))
    )
  }
  output
}

hp_pitch_log <- function(data, limit = 500L) {
  columns <- intersect(c("Date", "Time", "PitchNo", "Pitcher", "Batter", "Balls", "Strikes", "TaggedPitchType", "PitchCall", "PlayResult", "RelSpeed", "SpinRate", "InducedVertBreak", "HorzBreak", "RelHeight", "RelSide", "Extension", "PlateLocHeight", "PlateLocSide", "ExitSpeed", "Angle"), names(data))
  output <- data[seq_len(min(nrow(data), limit)), columns, drop = FALSE]
  names(output) <- gsub("([a-z])([A-Z])", "\\1_\\2", names(output))
  names(output) <- tolower(names(output))
  output
}

hp_pitching_analysis <- function(data, topic) {
  switch(topic,
    overview_arsenal = {
      metrics <- hp_pitch_metrics(data)
      list(
        metrics = list(hp_metric("pitches", "Pitches", nrow(data)), hp_metric("pitch_types", "Pitch types", nrow(metrics))),
        tables = hp_compact(list(
          hp_table("pitch_metrics", "Pitch Metrics by Pitch Type", metrics),
          if (hp_has(data, c("TaggedPitchType", "RelSpeed", "SpinRate"))) hp_table("bauer_grades", "Bauer Grades", hp_bauer_grades(data)),
          if (hp_has(data, c("TaggedPitchType", "PitchCall", "PlateLocSide", "PlateLocHeight"))) hp_table("pitch_results", "Pitch Type Results", hp_pitch_results(data)),
          if (hp_has(data, c("TaggedPitchType", "PitchofPA", "PlayResult"))) hp_table("performance_against", "Performance-Based Stats Against", hp_performance_against(data))
        )),
        charts = hp_compact(list(
          if (hp_has(data, c("TaggedPitchType", "HorzBreak", "InducedVertBreak"))) hp_chart("pitch_shape", "Pitch Shape", "scatter", data.frame(pitch_type = data$TaggedPitchType, horizontal_break = data$HorzBreak, induced_vertical_break = data$InducedVertBreak), "horizontal_break", "induced_vertical_break", "pitch_type")
        ))
      )
    },
    velocity_extension = {
      hp_require(data, c("TaggedPitchType", "RelSpeed"))
      metrics <- hp_pitch_metrics(data)
      list(
        metrics = list(
          hp_metric("avg_velocity", "Average velocity", hp_round(hp_mean(data$RelSpeed)), "mph"),
          hp_metric("max_velocity", "Maximum velocity", hp_round(if (any(is.finite(data$RelSpeed))) max(data$RelSpeed, na.rm = TRUE) else NA), "mph"),
          hp_metric("avg_extension", "Average extension", if ("Extension" %in% names(data)) hp_round(hp_mean(data$Extension), 2) else NA, "ft")
        ),
        tables = list(hp_table("velocity_by_pitch", "Velocity and Bauer Units", metrics[, c("pitch_type", "pitches", "avg_velocity", "max_velocity", "avg_spin", "bauer_units", "extension"), drop = FALSE])),
        charts = hp_compact(list(
          hp_chart("velocity_distribution", "Velocity Distribution", "distribution", hp_pitch_distribution(data, "RelSpeed"), "value", "density", "pitch_type"),
          if ("Extension" %in% names(data)) hp_chart("extension_distribution", "Extension Distribution", "distribution", hp_pitch_distribution(data, "Extension"), "value", "density", "pitch_type")
        ))
      )
    },
    pitch_break_shape = {
      hp_require(data, c("TaggedPitchType", "InducedVertBreak", "HorzBreak"))
      metrics <- hp_pitch_metrics(data)
      trajectory_columns <- c("TaggedPitchType", "PitchTrajectoryXc0", "PitchTrajectoryXc1", "PitchTrajectoryXc2", "PitchTrajectoryYc0", "PitchTrajectoryYc1", "PitchTrajectoryYc2", "PitchTrajectoryZc0", "PitchTrajectoryZc1", "PitchTrajectoryZc2")
      list(
        metrics = list(hp_metric("pitch_types", "Pitch types", nrow(metrics))),
        tables = list(hp_table("pitch_shape_averages", "Average Pitch Shape", metrics[, c("pitch_type", "pitches", "induced_vertical_break", "horizontal_break", "avg_velocity", "avg_spin"), drop = FALSE])),
        charts = hp_compact(list(
          hp_chart("pitch_shape", "Pitch Break & Shape", "scatter", data.frame(pitch_type = data$TaggedPitchType, horizontal_break = data$HorzBreak, induced_vertical_break = data$InducedVertBreak), "horizontal_break", "induced_vertical_break", "pitch_type"),
          if (hp_has(data, trajectory_columns)) hp_chart("pitch_map_3d", "3D Pitch Map", "trajectory_3d", hp_trajectory_3d(data), options = list(fallback = "pitch_location"))
        ))
      )
    },
    release_location = {
      location_columns <- c("TaggedPitchType", "PlateLocSide", "PlateLocHeight")
      release_columns <- c("TaggedPitchType", "RelSide", "RelHeight")
      if (!hp_has(data, location_columns) && !hp_has(data, release_columns)) hp_require(data, location_columns)
      list(
        metrics = list(hp_metric("zone_pct", "Zone rate", if (hp_has(data, location_columns)) hp_round(100 * mean(data$.in_zone, na.rm = TRUE)) else NA, "%")),
        tables = hp_compact(list(
          if (hp_has(data, c(location_columns, "PitchCall"))) hp_table("command", "Command Table", hp_command(data))
        )),
        charts = hp_compact(list(
          if (hp_has(data, release_columns)) hp_chart("release_clusters", "Release Point Cluster", "scatter", data.frame(pitch_type = data$TaggedPitchType, release_side = data$RelSide, release_height = data$RelHeight), "release_side", "release_height", "pitch_type"),
          if (hp_has(data, location_columns)) hp_chart("pitch_location", "Pitch Location", "zone_scatter", data.frame(pitch_type = data$TaggedPitchType, plate_side = data$PlateLocSide, plate_height = data$PlateLocHeight, result = if ("PitchCall" %in% names(data)) data$PitchCall else "Pitch"), "plate_side", "plate_height", "pitch_type", options = HP_ZONE)
        ))
      )
    },
    counts_finish = list(
      metrics = list(hp_metric("two_strike_pitches", "Two-strike pitches", sum(data$Strikes == 2, na.rm = TRUE))),
      tables = list(
        hp_table("count_performance", "Count Performance", hp_count_performance(data)),
        hp_table("count_usage", "Pitch Usage by Count", hp_count_usage(data)),
        hp_table("put_away", "Put Away Pitch Table", hp_put_away(data))
      ),
      charts = list(hp_chart("count_heatmap", "Count Performance", "heatmap", hp_count_performance(data), "count", "whiff_pct"))
    ),
    pitch_log = list(metrics = list(hp_metric("pitches", "Pitches", nrow(data))), tables = list(hp_table("pitch_log", "Pitch Log", hp_pitch_log(data))), charts = list()),
    stop("unsupported_pitching_topic")
  )
}
