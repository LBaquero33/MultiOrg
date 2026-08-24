HP_SCHEMA_VERSION <- 1L
HP_MODEL_VERSION <- "homeplate-r-analytics.v1"
HP_BENCHMARK_VERSION <- "homeplate-trackman-age-bands.v1"
HP_ZONE <- list(left = -0.7083, right = 0.7083, bottom = 1.5, top = 3.5)
HP_VELO_BANDS <- c(-Inf, 55, 60, 65, 70, 75, 80, 85, 90, Inf)
HP_VELO_LABELS <- c("55 or less", "56-60", "61-65", "66-70", "71-75", "76-80", "81-85", "86-90", "91+")

hp_null <- function(value) if (length(value) == 0L || all(is.na(value))) NULL else value

hp_num <- function(value) suppressWarnings(as.numeric(value))

hp_chr <- function(value) trimws(as.character(value))

hp_lower <- function(value) tolower(hp_chr(value))

hp_mean <- function(value) {
  value <- hp_num(value)
  if (!length(value) || all(is.na(value))) return(NA_real_)
  mean(value, na.rm = TRUE)
}

hp_pct <- function(numerator, denominator) {
  if (!is.finite(denominator) || denominator <= 0) return(NA_real_)
  100 * numerator / denominator
}

hp_round <- function(value, digits = 1L) {
  value <- hp_num(value)
  value[!is.finite(value)] <- NA_real_
  round(value, digits)
}

hp_missing <- function(data, columns) setdiff(columns, names(data))

hp_require <- function(data, columns) {
  missing <- hp_missing(data, columns)
  if (length(missing)) stop(structure(
    list(message = paste("missing_columns", paste(missing, collapse = ",")), missing = missing),
    class = c("hp_missing_columns", "error", "condition")
  ))
  invisible(TRUE)
}

hp_has <- function(data, columns) all(columns %in% names(data))

hp_compact <- function(items) Filter(Negate(is.null), items)

hp_table <- function(id, title, data, description = NULL) {
  if (is.null(data)) data <- data.frame()
  columns <- lapply(names(data), function(name) list(key = name, label = gsub("_", " ", name, fixed = TRUE)))
  rows <- unname(lapply(seq_len(nrow(data)), function(index) {
    row <- as.list(data[index, , drop = FALSE])
    lapply(row, function(value) {
      if (length(value) == 0L || is.na(value[[1]])) return(NULL)
      unname(value[[1]])
    })
  }))
  list(id = id, title = title, description = description, columns = columns, rows = rows)
}

hp_chart <- function(id, title, type, data, x = NULL, y = NULL, series = NULL, description = NULL, options = list()) {
  rows <- if (is.data.frame(data)) unname(lapply(seq_len(nrow(data)), function(i) as.list(data[i, , drop = FALSE]))) else data
  if (!length(options)) names(options) <- character()
  list(id = id, title = title, type = type, description = description, x = x, y = y, series = series, data = rows, options = options)
}

hp_metric <- function(key, label, value, unit = NULL, guidance = NULL, provisional = FALSE) {
  list(key = key, label = label, value = hp_null(value), unit = unit, guidance = guidance, provisional = provisional)
}

hp_prepare <- function(data) {
  data <- as.data.frame(data, stringsAsFactors = FALSE, check.names = FALSE)
  for (column in intersect(c(
    "Balls", "Strikes", "PitchofPA", "PAofInning", "RelSpeed", "SpinRate", "InducedVertBreak",
    "HorzBreak", "RelHeight", "RelSide", "Extension", "PlateLocHeight", "PlateLocSide",
    "ExitSpeed", "Angle", "Direction", "Distance", "Bearing", "EffectiveVelo", "ZoneSpeed"
  ), names(data))) data[[column]] <- hp_num(data[[column]])

  pitch_call <- if ("PitchCall" %in% names(data)) hp_lower(data$PitchCall) else rep(NA_character_, nrow(data))
  play_result <- if ("PlayResult" %in% names(data)) hp_lower(data$PlayResult) else rep(NA_character_, nrow(data))
  batted <- c("out", "single", "double", "triple", "homerun", "home run", "fielderschoice", "sacrifice")
  data$.pitch_call <- pitch_call
  data$.play_result <- play_result
  data$.swing <- pitch_call %in% c("foul", "whiff", batted)
  data$.whiff <- pitch_call == "whiff"
  data$.bip <- pitch_call %in% batted | play_result %in% batted
  if (all(c("PlateLocSide", "PlateLocHeight") %in% names(data))) {
    data$.in_zone <- !is.na(data$PlateLocSide) & !is.na(data$PlateLocHeight) &
      data$PlateLocSide >= HP_ZONE$left & data$PlateLocSide <= HP_ZONE$right &
      data$PlateLocHeight >= HP_ZONE$bottom & data$PlateLocHeight <= HP_ZONE$top
  } else data$.in_zone <- NA
  data$.chase <- data$.swing & !data$.in_zone
  if (all(c("Balls", "Strikes") %in% names(data))) data$.count <- paste0(data$Balls, "-", data$Strikes)
  if ("Date" %in% names(data)) data$.date <- as.character(as.Date(data$Date))
  data
}

hp_filter <- function(data, filters = list()) {
  output <- hp_prepare(data)
  if (!is.null(filters$start_date) && ".date" %in% names(output)) output <- output[output$.date >= filters$start_date, , drop = FALSE]
  if (!is.null(filters$end_date) && ".date" %in% names(output)) output <- output[output$.date <= filters$end_date, , drop = FALSE]
  if (length(filters$pitch_types) && "TaggedPitchType" %in% names(output)) output <- output[output$TaggedPitchType %in% filters$pitch_types, , drop = FALSE]
  if (length(filters$counts) && ".count" %in% names(output)) output <- output[output$.count %in% filters$counts, , drop = FALSE]
  if (length(filters$pitcher_throws) && "PitcherThrows" %in% names(output)) output <- output[output$PitcherThrows %in% filters$pitcher_throws, , drop = FALSE]
  if (length(filters$batter_sides) && "BatterSide" %in% names(output)) output <- output[output$BatterSide %in% filters$batter_sides, , drop = FALSE]
  output
}

hp_terminal_pa <- function(data) {
  hp_require(data, "PitchofPA")
  candidates <- intersect(c("GameID", "Date", "Inning", "Top.Bottom", "PAofInning", "Batter", "BatterId"), names(data))
  if (length(candidates) < 4L) return(data[!duplicated(data$PitchofPA, fromLast = TRUE), , drop = FALSE])
  ids <- do.call(paste, c(data[candidates], sep = "__"))
  split_rows <- split(seq_len(nrow(data)), ids)
  terminal <- vapply(split_rows, function(rows) rows[which.max(data$PitchofPA[rows])], integer(1))
  data[unname(terminal), , drop = FALSE]
}

hp_woba <- function(data) {
  if (!nrow(data)) return(rep(NA_real_, 0L))
  pr <- if ("PlayResult" %in% names(data)) hp_lower(data$PlayResult) else rep("", nrow(data))
  pc <- if ("PitchCall" %in% names(data)) hp_lower(data$PitchCall) else rep("", nrow(data))
  kb <- if ("KorBB" %in% names(data)) hp_lower(data$KorBB) else rep("", nrow(data))
  value <- rep(0, nrow(data))
  value[grepl("walk|bb", kb)] <- 0.69
  value[grepl("hitbypitch|hbp", kb) | grepl("hit_batter|hit by pitch", pc)] <- 0.72
  value[grepl("single", pr)] <- 0.88
  value[grepl("double", pr)] <- 1.25
  value[grepl("triple", pr)] <- 1.58
  value[grepl("homer|home run", pr)] <- 2.01
  value
}

hp_zone_bins <- function(data) {
  hp_require(data, c("PlateLocSide", "PlateLocHeight"))
  data$.zone_x <- cut(data$PlateLocSide, breaks = seq(HP_ZONE$left, HP_ZONE$right, length.out = 4), labels = c("Left", "Middle", "Right"), include.lowest = TRUE)
  data$.zone_y <- cut(data$PlateLocHeight, breaks = seq(HP_ZONE$bottom, HP_ZONE$top, length.out = 4), labels = c("Bottom", "Middle", "Top"), include.lowest = TRUE)
  data
}

hp_age_cohort <- function(age) {
  age <- suppressWarnings(as.numeric(age))
  if (!is.finite(age)) return("unknown")
  if (age <= 10) return("8-10")
  if (age <= 12) return("11-12")
  if (age <= 14) return("13-14")
  if (age <= 16) return("15-16")
  if (age <= 18) return("17-18")
  "college-adult"
}
