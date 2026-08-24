hp_model <- function(key, label, required, providers, chart_types = character(), description = "") {
  list(key = key, label = label, required_columns = required, providers = providers, chart_types = chart_types, description = description)
}

hp_catalog <- function() list(
  schema_version = HP_SCHEMA_VERSION,
  model_version = HP_MODEL_VERSION,
  benchmark_version = HP_BENCHMARK_VERSION,
  disciplines = list(
    pitching = list(
      topics = list(
        overview_arsenal = list(label = "Overview & Arsenal", models = c("pitch_metrics", "bauer_grades", "pitch_results", "performance_against")),
        velocity_extension = list(label = "Velocity & Extension", models = c("velocity_by_pitch", "bauer_units", "velocity_distribution", "extension_distribution")),
        pitch_break_shape = list(label = "Pitch Break & Shape", models = c("pitch_shape", "pitch_clusters", "pitch_map_3d")),
        release_location = list(label = "Release & Location", models = c("release_clusters", "pitch_location", "command")),
        counts_finish = list(label = "Counts & Finish", models = c("count_performance", "count_usage", "put_away")),
        pitch_log = list(label = "Pitch Log", models = c("pitch_log"))
      ),
      models = list(
        hp_model("pitch_metrics", "Pitch Metrics", c("TaggedPitchType", "RelSpeed", "SpinRate", "InducedVertBreak", "HorzBreak", "Extension", "RelHeight", "RelSide"), c("trackman", "rapsodo"), c("table")),
        hp_model("bauer_grades", "Bauer Grades", c("TaggedPitchType", "RelSpeed", "SpinRate"), c("trackman", "rapsodo"), c("table")),
        hp_model("pitch_results", "Pitch Type Results", c("TaggedPitchType", "PitchCall", "PlateLocSide", "PlateLocHeight"), c("trackman"), c("table")),
        hp_model("performance_against", "Performance Against", c("TaggedPitchType", "PlayResult"), c("trackman"), c("table")),
        hp_model("velocity_by_pitch", "Velocity by Pitch", c("TaggedPitchType", "RelSpeed"), c("trackman", "rapsodo"), c("line", "distribution")),
        hp_model("bauer_units", "Bauer Units", c("TaggedPitchType", "RelSpeed", "SpinRate"), c("trackman", "rapsodo"), c("table")),
        hp_model("velocity_distribution", "Velocity Distribution", c("TaggedPitchType", "RelSpeed"), c("trackman", "rapsodo"), c("distribution")),
        hp_model("extension_distribution", "Extension Distribution", c("TaggedPitchType", "Extension"), c("trackman", "rapsodo"), c("distribution")),
        hp_model("pitch_shape", "Pitch Shape", c("TaggedPitchType", "InducedVertBreak", "HorzBreak"), c("trackman", "rapsodo"), c("scatter")),
        hp_model("pitch_clusters", "Pitch Clusters", c("TaggedPitchType", "InducedVertBreak", "HorzBreak"), c("trackman", "rapsodo"), c("scatter")),
        hp_model("pitch_map_3d", "3D Pitch Map", c("TaggedPitchType", "PitchTrajectoryXc0", "PitchTrajectoryXc1", "PitchTrajectoryXc2", "PitchTrajectoryYc0", "PitchTrajectoryYc1", "PitchTrajectoryYc2", "PitchTrajectoryZc0", "PitchTrajectoryZc1", "PitchTrajectoryZc2"), c("trackman"), c("trajectory_3d", "scatter")),
        hp_model("release_clusters", "Release Point Cluster", c("TaggedPitchType", "RelSide", "RelHeight"), c("trackman", "rapsodo"), c("scatter")),
        hp_model("pitch_location", "Pitch Location", c("TaggedPitchType", "PlateLocSide", "PlateLocHeight"), c("trackman", "rapsodo"), c("scatter", "zone_grid")),
        hp_model("command", "Command", c("TaggedPitchType", "PitchCall", "PlateLocSide", "PlateLocHeight"), c("trackman", "rapsodo"), c("table")),
        hp_model("count_performance", "Count Performance", c("Balls", "Strikes", "PitchCall"), c("trackman"), c("table", "heatmap")),
        hp_model("count_usage", "Usage by Count", c("TaggedPitchType", "Balls", "Strikes"), c("trackman"), c("table", "heatmap")),
        hp_model("put_away", "Put Away Pitches", c("TaggedPitchType", "Strikes", "PitchCall"), c("trackman"), c("table")),
        hp_model("pitch_log", "Pitch Log", c("TaggedPitchType"), c("trackman", "rapsodo"), c("table"))
      )
    ),
    hitting = list(
      topics = list(
        overview_quality = list(label = "Overview & Quality", models = c("quality_scores", "hitting_summary")),
        contact_spray = list(label = "Contact & Spray", models = c("contact_quality", "spray_chart")),
        swing_decisions = list(label = "Swing Decisions", models = c("chase_profile", "swing_decision_matrix")),
        count_approach = list(label = "Count Approach", models = c("approach_by_count", "pitch_type_trust")),
        velocity_exposure = list(label = "Velocity Exposure", models = c("velocity_exposure")),
        zone_maps = list(label = "Zone Maps", models = c("zone_maps")),
        two_strikes = list(label = "Two Strikes", models = c("two_strike_summary", "two_strike_spray", "two_strike_zone"))
      ),
      models = list(
        hp_model("quality_scores", "Quality Scores", c("PitchCall"), c("trackman", "hittrax"), c("score")),
        hp_model("hitting_summary", "Hitting Summary", c("PitchCall"), c("trackman", "hittrax"), c("table")),
        hp_model("contact_quality", "Contact Quality", c("ExitSpeed", "Angle"), c("trackman", "hittrax"), c("scatter")),
        hp_model("spray_chart", "Spray Chart", c("ExitSpeed", "Angle", "Direction"), c("trackman", "hittrax"), c("spray")),
        hp_model("chase_profile", "Chase Profile", c("PitchCall", "PlateLocSide", "PlateLocHeight"), c("trackman"), c("bar")),
        hp_model("swing_decision_matrix", "Swing Decision Matrix", c("TaggedPitchType", "Balls", "Strikes", "PitchCall"), c("trackman"), c("heatmap")),
        hp_model("approach_by_count", "Approach by Count", c("Balls", "Strikes", "PitchCall"), c("trackman"), c("table")),
        hp_model("pitch_type_trust", "Pitch Type Trust", c("TaggedPitchType", "PitchCall", "PlayResult"), c("trackman"), c("table")),
        hp_model("velocity_exposure", "Velocity Exposure", c("RelSpeed", "PitchCall"), c("trackman", "hittrax"), c("table", "bar")),
        hp_model("zone_maps", "Zone Maps", c("PlateLocSide", "PlateLocHeight", "PitchCall"), c("trackman"), c("zone_grid")),
        hp_model("two_strike_summary", "Two Strike Approach", c("Strikes", "PitchCall", "PlateLocSide", "PlateLocHeight"), c("trackman"), c("table")),
        hp_model("two_strike_spray", "Two Strike Spray", c("Strikes", "PitchCall", "ExitSpeed", "Angle", "Direction"), c("trackman"), c("spray")),
        hp_model("two_strike_zone", "Two Strike Zone", c("Strikes", "PitchCall", "PlateLocSide", "PlateLocHeight"), c("trackman"), c("zone_grid"))
      )
    )
  )
)

hp_catalog_models <- function(discipline) hp_catalog()$disciplines[[discipline]]$models

hp_catalog_for_source <- function(discipline, provider, columns) {
  models <- hp_catalog_models(discipline)
  lapply(models, function(model) {
    required <- model$required_columns
    if (provider == "hittrax" && model$key %in% c("quality_scores", "hitting_summary")) required <- c("ExitSpeed", "Angle")
    missing <- setdiff(required, columns)
    provider_ok <- provider %in% model$providers
    c(model, list(
      available = provider_ok && !length(missing),
      missing_columns = unname(missing),
      unavailable_reason = if (!provider_ok) paste0("Not supported for ", provider) else if (length(missing)) paste("Missing", paste(missing, collapse = ", ")) else NULL
    ))
  })
}
