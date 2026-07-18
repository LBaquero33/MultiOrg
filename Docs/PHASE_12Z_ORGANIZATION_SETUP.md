# Phase 12Z organization setup architecture

Organization setup is a resumable orchestration layer over authoritative Home Plate data. It does not create parallel season, team, roster, registration, facility, communication, finance, or scheduling records.

## Entry and presentation

- Owners and organization administrators enter from Overview or Organization Administration → Setup & Launch.
- Verified platform administrators can enter from the selected organization’s platform detail. This is an explicit assisted path and does not grant organization membership or ownership.
- macOS and wide iPad layouts use a persistent checklist sidebar, detail workspace, and footer actions. Compact iPad and iPhone layouts use a step menu, single-column detail, and the same footer actions.
- Setup can be dismissed, reopened, resumed at its persisted step, and reviewed after completion.

## Authoritative data mapping

| Setup step | Authoritative destination |
| --- | --- |
| Organization basics | `sd_orgs` |
| Season | `sd_seasons` |
| Teams | `sd_teams` |
| Staff | validated setup draft; final credentials and assignments use Members / `sd_coach_team_assignments` |
| Players and families | validated CSV setup draft; final identities, roster assignment, and links use Members / `sd_player_team_memberships` / `sd_parent_child_links` |
| Registration and fees | draft `sd_registration_offerings`; no collection or provider send |
| Facilities | `sd_facilities` |
| Communication | `sd_communication_policies`; no provider send |
| First baseball action | draft `sd_team_events` |

`sd_organization_setup_sessions`, `sd_organization_setup_steps`, and `sd_organization_setup_drafts` contain wizard state only. `sd_organization_setup_mutations` provides retry receipts, `sd_organization_setup_entities` records setup provenance, and `sd_organization_setup_audit_logs` provides the immutable setup audit trail.

Launch readiness is computed from live authoritative records. The minimum viable organization is:

1. active organization;
2. organization name and timezone;
3. active or default season; and
4. active team assigned to that season.

Staff, players/families, registration/fees, facilities, communication, and the first baseball action are useful but optional and do not falsely block launch.

## Authorization and concurrency

The `organization-setup` Edge Function is the only client write boundary. `sd_resolve_setup_capabilities` authorizes active owners/admins and separately verified platform administrators. Coaches, players, parents, inactive members, and unverified users fail closed.

Every mutation requires a UUID request ID and writes a response receipt. Session mutations use an expected version; stale requests return `stale_setup_version`. The Swift state model also verifies request token and organization context before publishing data or errors, so superseded or cancelled requests cannot overwrite newer state.

## Temporary Marist test mode

The test surface is unavailable unless all guards agree:

```text
HOME_PLATE_SETUP_TEST_MODE=true
HOME_PLATE_SETUP_TEST_ORGANIZATION_ID=<stable Marist organization UUID>
HOME_PLATE_ENVIRONMENT=local|development|staging|testflight
```

The client and server match the configured UUID exactly; the organization name is never used as identity. The actor must also be an authorized owner/admin or platform administrator.

The default action is **Reset Wizard Progress Only** and preserves every business record. A selective preview can list only records carrying setup-test provenance. Selective deletion is limited to explicitly supported setup-created entity types and fails if other data references them. Payments, refunds, invoices, expenses, registration applications, event/practice/game operations, chat messages, notification delivery, and audit history are always protected.

A full organization reset is intentionally unavailable because the current architecture cannot prove that all organization data is synthetic and disposable. Production fails closed when the flags are absent or the environment is not permitted.

## Deployment requirements

Local client behavior does not require deployment for builds or tests, but the live wizard requires both of these release operations in order:

1. apply `20260718160000_complete_organization_setup.sql` after the Phase 12 migration chain;
2. deploy the `organization-setup` Edge Function with standard Supabase secrets.

Temporary Marist configuration is optional and must use the stable UUID from the target environment. No setup test flag should be configured in normal production.
