# Replicating This App For A New Organization

This repo is set up so the **org-specific** values live in `Configs/Secrets.xcconfig` and are injected into the app at build time (via `project.yml` → `Info.plist`).

## What changes per org
- App display name (shown under icon + on Login)
- Bundle identifiers (iOS + macOS)
- Supabase host + anon key
- Stripe subscription Payment Link (optional)
- Support email + website host
- (Optional) legacy login email domain

## One-command scaffold (local)
Use the generator:

```bash
cd /path/to/DHD-Self-Development-iOS

python3 tools/replicate_org.py \
  --slug acme \
  --app-name "ACME Player Development" \
  --ios-bundle-id com.acme.selfdevelopment \
  --mac-bundle-id com.acme.selfdevelopment.mac \
  --supabase-host YOURPROJECT.supabase.co \
  --supabase-anon-key "YOUR_ANON_KEY" \
  --website-host acmebaseball.com \
  --support-email support@acmebaseball.com \
  --stripe-subscribe-url buy.stripe.com/REPLACE_ME
```

Output:
- Creates a new folder next to this repo: `DHD-Self-Development-iOS-acme/`
- Writes `Configs/Secrets.xcconfig` in the new folder (from the example template)
- Updates bundle IDs in the new folder’s `project.yml`
- Regenerates the Xcode project using the bundled `tools/xcodegen`

Then open:
- `HomePlate-acme/HomePlate.xcodeproj`

## Notes
- In `.xcconfig`, `https://...` is treated as a comment (`//`).  
  For URLs (Stripe + website), store them **without** the scheme, and the app prepends `https://` at runtime.
- `Configs/Secrets.xcconfig` is **gitignored** on purpose (it contains secrets).

## “Master app” idea (future)
Two viable directions:
1) **Multi-tenant single app + single Supabase**: add `org_id` to all tables + org-scoped RLS. Biggest refactor, but one codebase + one app.
2) **Per-org app + per-org Supabase**: keep this replication approach, then optionally build a separate “control plane” (web/admin app) that:
   - stores org configs
   - runs the generator
   - provisions Supabase projects and deploys functions/migrations
