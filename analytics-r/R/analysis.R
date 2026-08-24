hp_guidance <- function(discipline, topic, result, sample) {
  base <- if (discipline == "pitching") {
    switch(topic,
      overview_arsenal = "Use pitch characteristics and results together; shape alone does not determine effectiveness.",
      velocity_extension = "Compare velocity and extension by pitch type and date range rather than treating one maximum reading as the full story.",
      pitch_break_shape = "Look for distinct pitch shapes and repeatable movement clusters before changing an athlete's arsenal.",
      release_location = "Tighter release clusters and intentional zone-edge usage generally indicate more repeatable command.",
      counts_finish = "Review which pitches create strikes early and which pitches generate chase or whiff with two strikes.",
      pitch_log = "Use the pitch log to audit individual events behind the summaries.",
      "Review the selected pitching data in context."
    )
  } else {
    switch(topic,
      overview_quality = "Quality scores compare this sample with the athlete's Home Plate age cohort and remain provisional until the minimum sample is reached.",
      contact_spray = "Use exit velocity, launch angle, direction, and outcomes together to understand contact quality.",
      swing_decisions = "Strong decisions combine controlled chase with competitive swings on hittable pitches.",
      count_approach = "Compare swing and contact behavior across counts to identify where the approach changes.",
      velocity_exposure = "Small samples in a velocity band should guide questions, not produce a permanent label.",
      zone_maps = "Zone maps describe this selected sample and should be interpreted with pitch counts in each cell.",
      two_strikes = "Two-strike performance balances zone coverage, chase control, contact, and productive outcomes.",
      "Review the selected hitting data in context."
    )
  }
  list(summary = base, sample_note = paste("Analysis includes", sample, "source rows."))
}

hp_analyze <- function(data, request) {
  discipline <- tolower(request$discipline %||% "")
  topic <- tolower(request$module %||% "")
  provider <- tolower(request$provider %||% "trackman")
  if (!discipline %in% c("hitting", "pitching")) stop("invalid_discipline")
  filtered <- hp_filter(data, request$filters %||% list())
  if (!nrow(filtered)) stop("no_rows_for_filters")
  availability <- hp_catalog_for_source(discipline, provider, names(filtered))
  result <- if (discipline == "pitching") hp_pitching_analysis(filtered, topic) else hp_hitting_analysis(filtered, topic, request$benchmarks %||% list())
  list(
    schema_version = HP_SCHEMA_VERSION,
    model_version = HP_MODEL_VERSION,
    benchmark_version = HP_BENCHMARK_VERSION,
    generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    discipline = discipline,
    module = topic,
    filters = request$filters %||% list(),
    sample_summary = list(rows = nrow(filtered), dates = if (".date" %in% names(filtered)) length(unique(filtered$.date)) else NULL, provider = provider),
    source_coverage = list(columns = names(filtered), models = availability),
    benchmark_summary = request$benchmark_summary %||% list(status = "building", cohort = request$age_cohort %||% "unknown"),
    summary_metrics = result$metrics %||% list(),
    tables = result$tables %||% list(),
    charts = result$charts %||% list(),
    guidance = hp_guidance(discipline, topic, result, nrow(filtered)),
    warnings = result$warnings %||% list(),
    unavailable_reasons = unname(lapply(Filter(function(model) !isTRUE(model$available), availability), function(model) list(model = model$key, reason = model$unavailable_reason)))
  )
}

hp_read_source <- function(path_or_url, file_type = "csv") {
  if (!grepl("^https://", path_or_url) && !file.exists(path_or_url)) stop("source_not_found")
  separator <- if (tolower(file_type) == "tsv") "\t" else ","
  utils::read.table(path_or_url, header = TRUE, sep = separator, quote = "\"", comment.char = "", check.names = FALSE, stringsAsFactors = FALSE, fill = TRUE)
}

.hp_analysis_cache <- new.env(parent = emptyenv())

hp_cache_get <- function(key, ttl_seconds = 900) {
  if (is.null(key) || !grepl("^[a-f0-9]{64}$", key) || !exists(key, envir = .hp_analysis_cache, inherits = FALSE)) return(NULL)
  entry <- get(key, envir = .hp_analysis_cache, inherits = FALSE)
  if (as.numeric(Sys.time()) - entry$created_at > ttl_seconds) {
    rm(list = key, envir = .hp_analysis_cache)
    return(NULL)
  }
  entry$value
}

hp_cache_set <- function(key, value, max_entries = 200L) {
  if (is.null(key) || !grepl("^[a-f0-9]{64}$", key)) return(invisible(value))
  assign(key, list(created_at = as.numeric(Sys.time()), value = value), envir = .hp_analysis_cache)
  keys <- ls(.hp_analysis_cache, all.names = TRUE)
  if (length(keys) > max_entries) {
    created <- vapply(keys, function(item) get(item, envir = .hp_analysis_cache)$created_at, numeric(1))
    rm(list = keys[order(created)][seq_len(length(keys) - max_entries)], envir = .hp_analysis_cache)
  }
  invisible(value)
}

hp_cache_delete <- function(key) {
  if (is.null(key) || !grepl("^[a-f0-9]{64}$", key)) return(FALSE)
  if (!exists(key, envir = .hp_analysis_cache, inherits = FALSE)) return(FALSE)
  rm(list = key, envir = .hp_analysis_cache)
  TRUE
}
