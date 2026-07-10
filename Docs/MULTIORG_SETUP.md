# Multi‑Org Setup (Single Supabase Project)

This repo is a **multi‑organization** variant of the app:
- Users pick an **Organization** first, then sign in with **username + password**.
- Username is **org‑scoped** and resolves to a real Supabase Auth email (password reset still works).

## 1) Apply DB migrations
Run all SQL in `supabase/migrations/` against your Supabase project.

Minimum required for org-first login:
- `20260524000100_sd_multiorg_foundation.sql`

## 2) Deploy Edge Function: `org_login`
Function source:
- `supabase/functions/org_login/index.ts`

Required Edge Function secrets:
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY` (server-only; never ship to clients)

## 3) Seed orgs + memberships + usernames
You need, at minimum:
- 1 row in `sd_orgs` for each org you want in the dropdown
- 1 row in `sd_org_memberships` for each user who should have access to an org
- 1 row in `sd_org_usernames` for each `(org, username) → user_id` mapping

### Suggested first org
`sd_orgs` includes a default `demo` org insertion if the table is empty. Rename or delete it if you want.

## Notes
- In this build, **Create Account** from the UI is disabled intentionally. Accounts should be created/administered by the org owner/admin flow.

