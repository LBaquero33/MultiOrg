source("R/load.R")

#* @filter secure
function(req, res) {
  if (req$PATH_INFO %in% c("/healthz", "/readyz")) return(plumber::forward())
  body <- req$postBody %||% ""
  if (!hp_verify_service_request(req, body)) {
    res$status <- 401
    return(list(error = "service_authentication_required"))
  }
  plumber::forward()
}

#* @get /healthz
function() list(status = "ok", service = "homeplate-r-analytics", model_version = HP_MODEL_VERSION)

#* @get /readyz
function() list(status = "ready", catalog_version = HP_SCHEMA_VERSION, disciplines = c("hitting", "pitching"))

#* @serializer json list(na="null", auto_unbox=TRUE)
#* @get /v1/catalog
function() hp_catalog()

#* @serializer json list(na="null", auto_unbox=TRUE)
#* @post /v1/analyze
function(req, res) {
  payload <- tryCatch(jsonlite::fromJSON(req$postBody, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(payload) || is.null(payload$source_url)) {
    res$status <- 400
    return(list(error = "invalid_analysis_request"))
  }
  tryCatch({
    cached <- hp_cache_get(payload$cache_key %||% NULL)
    if (!is.null(cached)) return(c(cached, list(cache_status = "hit")))
    source <- hp_read_source(payload$source_url, payload$file_type %||% "csv")
    result <- hp_analyze(source, payload)
    hp_cache_set(payload$cache_key %||% NULL, result)
    c(result, list(cache_status = "miss"))
  }, hp_missing_columns = function(error) {
    res$status <- 422
    list(error = "missing_required_source_columns", missing_columns = error$missing)
  }, error = function(error) {
    res$status <- 422
    list(error = if (grepl("^[a-z0-9_]+$", conditionMessage(error))) conditionMessage(error) else "analysis_failed")
  })
}

#* @serializer json list(na="null", auto_unbox=TRUE)
#* @post /v1/precompute
function(req, res) {
  payload <- tryCatch(jsonlite::fromJSON(req$postBody, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(payload) || is.null(payload$source_url)) {
    res$status <- 400
    return(list(error = "invalid_precompute_request"))
  }
  source <- hp_read_source(payload$source_url, payload$file_type %||% "csv")
  modules <- if (payload$discipline == "pitching") names(hp_catalog()$disciplines$pitching$topics) else names(hp_catalog()$disciplines$hitting$topics)
  results <- lapply(modules, function(module) tryCatch(hp_analyze(source, c(payload, list(module = module))), error = function(error) list(module = module, error = conditionMessage(error))))
  list(model_version = HP_MODEL_VERSION, results = results)
}

#* @serializer json list(na="null", auto_unbox=TRUE)
#* @post /v1/benchmarks/build
function(req, res) {
  payload <- tryCatch(jsonlite::fromJSON(req$postBody, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(payload) || is.null(payload$source_url) || is.null(payload$athlete_column)) {
    res$status <- 400
    return(list(error = "invalid_benchmark_request"))
  }
  tryCatch({
    source <- hp_read_source(payload$source_url, payload$file_type %||% "csv")
    hp_build_benchmark(
      source,
      payload$discipline %||% "",
      payload$cohort %||% "unknown",
      payload$athlete_column
    )
  }, error = function(error) {
    res$status <- 422
    list(error = if (grepl("^[a-z0-9_]+$", conditionMessage(error))) conditionMessage(error) else "benchmark_build_failed")
  })
}

#* @serializer json list(na="null", auto_unbox=TRUE)
#* @post /v1/cache/invalidate
function(req, res) {
  payload <- tryCatch(jsonlite::fromJSON(req$postBody, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(payload) || is.null(payload$cache_key)) {
    res$status <- 400
    return(list(error = "invalid_cache_invalidation_request"))
  }
  list(invalidated = hp_cache_delete(payload$cache_key))
}
