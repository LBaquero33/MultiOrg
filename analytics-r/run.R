source("R/load.R")

port <- suppressWarnings(as.integer(Sys.getenv("PORT", "8000")))
if (!is.finite(port)) port <- 8000L

api <- plumber::plumb("plumber.R")
api$run(host = "0.0.0.0", port = port, docs = FALSE)
