# Home Plate R Analytics

Private Plumber service for on-demand TrackMan, HitTrax, and Rapsodo analysis.
The service owns model calculations only. Supabase remains responsible for user
authentication, player authorization, source-file ownership, and signed storage
URLs.

## Required environment

- `HOME_PLATE_ANALYTICS_HMAC_SECRET`: shared high-entropy request-signing secret.
- `PORT`: HTTP port; defaults to `8000`.

Never expose the HMAC secret to a browser or native client. Only the
`player-development-analytics` Edge Function may call this service.

## Local verification

```sh
/Library/Frameworks/R.framework/Resources/bin/R --vanilla -f tests/testthat.R
docker build -t homeplate-r-analytics .
docker run --rm -p 8000:8000 \
  -e HOME_PLATE_ANALYTICS_HMAC_SECRET=local-only-secret \
  homeplate-r-analytics
```

`GET /healthz` and `GET /readyz` are intentionally unauthenticated. Catalog,
analysis, precompute, and cache invalidation endpoints require a valid signed
request and reject expired timestamps or replayed nonces.

## Render

Create a Docker web service using this directory as the root. Configure
`HOME_PLATE_ANALYTICS_HMAC_SECRET` as a secret and use `/readyz` for the health
check. After Render assigns the service URL, set the following Supabase function
secrets with the same HMAC value:

- `HOME_PLATE_ANALYTICS_URL`
- `HOME_PLATE_ANALYTICS_HMAC_SECRET`

The source applications under the external Marist and MLB Attack directories
are reference implementations and are never modified or deployed with this
service.
