HP_BENCHMARK_PERCENTILES <- c(5, 10, 25, 50, 75, 90, 95)

hp_benchmark_metric <- function(values) {
  values <- hp_num(values)
  values <- values[is.finite(values)]
  if (length(values) < 2L) return(NULL)
  list(
    percentiles = HP_BENCHMARK_PERCENTILES,
    percentile_values = unname(hp_round(stats::quantile(
      values,
      probs = HP_BENCHMARK_PERCENTILES / 100,
      names = FALSE,
      na.rm = TRUE,
      type = 7
    ), 3))
  )
}

hp_benchmark_athlete_rows <- function(data, athlete_column, discipline) {
  hp_require(data, athlete_column)
  prepared <- hp_prepare(data)
  athlete_ids <- unique(hp_chr(prepared[[athlete_column]]))
  athlete_ids <- athlete_ids[nzchar(athlete_ids) & !is.na(athlete_ids)]
  rows <- lapply(athlete_ids, function(athlete_id) {
    sample <- prepared[hp_chr(prepared[[athlete_column]]) == athlete_id, , drop = FALSE]
    if (discipline == "pitching") {
      data.frame(
        average_velocity = if ("RelSpeed" %in% names(sample)) hp_mean(sample$RelSpeed) else NA,
        maximum_velocity = if ("RelSpeed" %in% names(sample) && any(is.finite(sample$RelSpeed))) max(sample$RelSpeed, na.rm = TRUE) else NA,
        average_spin_rate = if ("SpinRate" %in% names(sample)) hp_mean(sample$SpinRate) else NA,
        induced_vertical_break = if ("InducedVertBreak" %in% names(sample)) hp_mean(sample$InducedVertBreak) else NA,
        horizontal_break = if ("HorzBreak" %in% names(sample)) hp_mean(sample$HorzBreak) else NA,
        extension = if ("Extension" %in% names(sample)) hp_mean(sample$Extension) else NA
      )
    } else {
      raw <- hp_quality_scores(sample, list())$raw
      as.data.frame(raw, stringsAsFactors = FALSE)
    }
  })
  if (!length(rows)) return(data.frame())
  do.call(rbind, rows)
}

hp_build_benchmark <- function(data, discipline, cohort, athlete_column) {
  discipline <- tolower(discipline %||% "")
  if (!discipline %in% c("hitting", "pitching")) stop("invalid_discipline")
  hp_require(data, athlete_column)
  identities <- unique(hp_chr(data[[athlete_column]]))
  identities <- identities[nzchar(identities) & !is.na(identities)]
  distinct_athletes <- length(identities)
  event_count <- if (discipline == "hitting") nrow(hp_batted_balls(hp_prepare(data))) else nrow(data)
  minimum_events <- if (discipline == "hitting") 500L else 2000L
  status <- if (distinct_athletes >= 30L && event_count >= minimum_events) "published" else "building"
  output <- list(
    benchmark_version = HP_BENCHMARK_VERSION,
    discipline = discipline,
    cohort = cohort,
    status = status,
    sample_size = list(distinct_athletes = distinct_athletes, events = event_count),
    thresholds = list(distinct_athletes = 30L, events = minimum_events),
    metrics = list()
  )
  if (status != "published") return(output)
  athlete_rows <- hp_benchmark_athlete_rows(data, athlete_column, discipline)
  output$metrics <- hp_compact(lapply(athlete_rows, hp_benchmark_metric))
  output
}
