# Apple transaction verifier service

## Why this service exists

Supabase Edge Runtime's Node compatibility layer does not implement the X.509
operations required by Apple's official App Store Server Library. In the
runtime source, `X509Certificate.prototype.verify` throws a not-implemented
error. The library calls that API to verify the intermediate certificate
against an Apple root and the leaf certificate against the intermediate. It
also requires `X509Certificate.raw`, `infoAccess`, and `toString` later in the
chain and OCSP paths.

The service in `apple-verifier-service` runs Apple's official library on Node
20. Supabase remains responsible for user authorization, idempotency,
subscription persistence, and entitlement updates. The verifier receives no
Supabase service-role credential.

## Trust boundary

1. The authenticated app calls `verify-apple-player-subscription` as before.
2. The Edge Function validates the actor and deterministic app account token.
3. The Edge Function sends the Apple JWS, expected token, and a one-time nonce
   to the Node verifier over HTTPS with a service bearer token.
4. Apple's official library validates the certificate chain, Apple certificate
   extensions, certificate dates/OCSP policy, and JWS signature.
5. The verifier validates bundle, environment, product, app account token, and
   transaction identifiers.
6. The verifier returns only the required fields in a nonce-bound,
   timestamped HMAC envelope.
7. The Edge Function verifies the HMAC, nonce, freshness, and transaction
   context before running the existing idempotent Supabase entitlement sync.

## Node service environment

- `APPLE_BUNDLE_ID`
- `APPLE_ENVIRONMENT` (`sandbox` or `production`)
- `APPLE_APP_APPLE_ID` (required in production)
- `APPLE_ROOT_CA_CERTIFICATES_BASE64` (JSON array of DER certificates encoded
  with standard base64)
- `APPLE_ENABLE_ONLINE_CHECKS` (sandbox-only operational override; production
  is always enabled)
- `APPLE_VERIFIER_SERVICE_TOKEN` (random secret, at least 32 characters)
- `APPLE_VERIFIER_RESPONSE_HMAC_SECRET` (different random secret, at least 32
  characters)

## Supabase Edge Function secrets

- `APPLE_VERIFIER_SERVICE_URL` (HTTPS origin of the Node service)
- `APPLE_VERIFIER_SERVICE_TOKEN` (same request secret)
- `APPLE_VERIFIER_RESPONSE_HMAC_SECRET` (same response signing secret)

Keep the existing Apple and Supabase secrets. Generate the two service secrets
independently. Do not expose either secret to the Apple clients.

## Deployment order

Do not deploy from an unreviewed working tree.

1. Deploy `apple-verifier-service/Dockerfile` to a standard Node 20-compatible
   service and configure its environment.
2. Confirm `GET /health` returns marker `home_plate_apple_verifier_v1`.
3. Set the three Supabase gateway secrets.
4. Deploy only `verify-apple-player-subscription`.
5. Retry the existing unfinished StoreKit transaction. No new purchase is
   required.

The App Store Server Notifications function also uses Apple's Node verifier
inside Supabase Edge Runtime and must be routed through this service before
production notification processing is considered reliable. That separate
notification migration is intentionally outside the purchase-recovery change.
