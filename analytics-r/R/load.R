service_root <- normalizePath(
  getOption("homeplate.analytics.root", getwd()),
  winslash = "/",
  mustWork = TRUE
)
for (path in c(
  "R/common.R",
  "R/catalog.R",
  "R/pitching.R",
  "R/hitting.R",
  "R/benchmarks.R",
  "R/analysis.R",
  "R/security.R"
)) source(file.path(service_root, path), local = .GlobalEnv)
