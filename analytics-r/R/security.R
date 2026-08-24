hp_constant_time_equal <- function(left, right) {
  left <- charToRaw(as.character(left))
  right <- charToRaw(as.character(right))
  if (length(left) != length(right)) return(FALSE)
  difference <- 0L
  for (index in seq_along(left)) difference <- bitwOr(difference, bitwXor(as.integer(left[[index]]), as.integer(right[[index]])))
  identical(difference, 0L)
}

.hp_seen_nonces <- new.env(parent = emptyenv())

hp_claim_nonce <- function(nonce, timestamp, ttl_seconds = 180) {
  now <- as.numeric(Sys.time())
  keys <- ls(.hp_seen_nonces, all.names = TRUE)
  if (length(keys)) {
    stale <- keys[vapply(keys, function(key) now - get(key, envir = .hp_seen_nonces) > ttl_seconds, logical(1))]
    if (length(stale)) rm(list = stale, envir = .hp_seen_nonces)
  }
  if (exists(nonce, envir = .hp_seen_nonces, inherits = FALSE)) return(FALSE)
  assign(nonce, as.numeric(timestamp), envir = .hp_seen_nonces)
  TRUE
}

hp_verify_service_request <- function(req, body) {
  secret <- Sys.getenv("HOME_PLATE_ANALYTICS_HMAC_SECRET", "")
  if (!nzchar(secret)) return(FALSE)
  timestamp <- req$HTTP_X_HOME_PLATE_TIMESTAMP %||% ""
  nonce <- req$HTTP_X_HOME_PLATE_NONCE %||% ""
  signature <- req$HTTP_X_HOME_PLATE_SIGNATURE %||% ""
  if (!grepl("^[0-9]{10,13}$", timestamp) || !grepl("^[A-Za-z0-9_-]{16,100}$", nonce)) return(FALSE)
  seconds <- as.numeric(timestamp)
  if (seconds > 1e12) seconds <- seconds / 1000
  if (!is.finite(seconds) || abs(as.numeric(Sys.time()) - seconds) > 120) return(FALSE)
  digest_body <- digest::digest(body, algo = "sha256", serialize = FALSE)
  expected <- digest::hmac(secret, paste(timestamp, nonce, digest_body, sep = "."), algo = "sha256", serialize = FALSE)
  hp_constant_time_equal(expected, signature) && hp_claim_nonce(nonce, seconds)
}

`%||%` <- function(left, right) if (is.null(left) || !length(left)) right else left
