import {
  assert,
  assertEquals,
  assertMatch,
  assertRejects,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  canApplyGoogleEdit,
  externalEventPatch,
  googleAuthorizationURL,
  openSecret,
  pkceChallenge,
  sealSecret,
  sourceToGoogleEvent,
} from "./calendar_integrations.ts";

const key = btoa(String.fromCharCode(...new Uint8Array(32).fill(7)));

Deno.test("calendar credentials round trip through authenticated AES-GCM encryption", async () => {
  const sealed = await sealSecret("refresh-token-example", key);
  assertMatch(sealed, /^v1\./);
  assert(!sealed.includes("refresh-token-example"));
  assertEquals(await openSecret(sealed, key), "refresh-token-example");
  await assertRejects(() =>
    openSecret(sealed, btoa(String.fromCharCode(...new Uint8Array(32).fill(8))))
  );
});

Deno.test("Google OAuth uses PKCE, offline access, opaque state, and the narrow event scope", async () => {
  const verifier = "verifier-value-with-enough-entropy-for-test";
  const challenge = await pkceChallenge(verifier);
  const url = new URL(googleAuthorizationURL({
    clientId: "client-id",
    redirectUri: "https://example.com/callback",
    state: "opaque-state",
    codeChallenge: challenge,
  }));
  assertEquals(url.searchParams.get("state"), "opaque-state");
  assertEquals(url.searchParams.get("access_type"), "offline");
  assertEquals(url.searchParams.get("code_challenge_method"), "S256");
  assertEquals(
    url.searchParams.get("scope"),
    "https://www.googleapis.com/auth/calendar.events",
  );
});

Deno.test("Home Plate event mapping keeps only opaque identifiers in private properties", () => {
  const mapped = sourceToGoogleEvent({
    kind: "sd_team_events",
    id: "11111111-1111-4111-8111-111111111111",
    organizationId: "22222222-2222-4222-8222-222222222222",
    teamId: "33333333-3333-4333-8333-333333333333",
    title: "Practice",
    description: "Bring turf shoes",
    startAt: "2026-08-22T20:00:00.000Z",
    endAt: "2026-08-22T22:00:00.000Z",
    location: "Home Plate Facility",
    status: "scheduled",
    updatedAt: null,
  });
  assertEquals(mapped.summary, "Practice");
  assertEquals(
    mapped.extendedProperties?.private?.homePlateSourceKind,
    "sd_team_events",
  );
  assertEquals(mapped.extendedProperties?.private?.homePlateReadOnly, "false");
  assert(!JSON.stringify(mapped).includes("token"));
});

Deno.test("booking calendar entries are explicitly read-only", () => {
  const mapped = sourceToGoogleEvent({
    kind: "sd_facility_bookings",
    id: "11111111-1111-4111-8111-111111111111",
    organizationId: "22222222-2222-4222-8222-222222222222",
    teamId: null,
    title: "Bullpen booking",
    description: null,
    startAt: "2026-08-22T20:00:00.000Z",
    endAt: "2026-08-22T21:00:00.000Z",
    location: "Mound 1",
    status: "approved",
    updatedAt: null,
  });
  assertEquals(mapped.extendedProperties?.private?.homePlateReadOnly, "true");
  assert(mapped.description?.includes("cannot be changed"));
});

Deno.test("external patches reject malformed times and preserve normalized fields", () => {
  assertEquals(externalEventPatch({ summary: "Practice" }), null);
  assertEquals(
    externalEventPatch({
      summary: "Practice",
      start: { dateTime: "2026-08-22T22:00:00Z" },
      end: { dateTime: "2026-08-22T21:00:00Z" },
    }),
    null,
  );
  assertEquals(
    externalEventPatch({
      summary: " Practice ",
      description: " Bring water ",
      location: " Field 1 ",
      start: { dateTime: "2026-08-22T20:00:00Z" },
      end: { dateTime: "2026-08-22T21:00:00Z" },
    }),
    {
      title: "Practice",
      description: "Bring water",
      location: "Field 1",
      startAt: "2026-08-22T20:00:00.000Z",
      endAt: "2026-08-22T21:00:00.000Z",
    },
  );
});

Deno.test("two-way edits fail closed by role, capability, and source type", () => {
  assert(
    canApplyGoogleEdit({
      role: "owner",
      capabilities: [],
      sourceKind: "sd_events",
    }),
  );
  assert(
    canApplyGoogleEdit({
      role: "admin",
      capabilities: [],
      sourceKind: "sd_team_events",
    }),
  );
  assert(canApplyGoogleEdit({
    role: "coach",
    capabilities: ["manage_practice_event"],
    sourceKind: "sd_team_events",
    eventType: "practice",
  }));
  assert(
    !canApplyGoogleEdit({
      role: "coach",
      capabilities: ["view_team_schedule"],
      sourceKind: "sd_team_events",
      eventType: "practice",
    }),
  );
  assert(
    !canApplyGoogleEdit({
      role: "player",
      capabilities: [],
      sourceKind: "sd_events",
    }),
  );
  assert(
    !canApplyGoogleEdit({
      role: "owner",
      capabilities: [],
      sourceKind: "sd_facility_bookings",
    }),
  );
});

Deno.test("calendar integration backfills existing sources and removes deleted events", async () => {
  const migration = await Deno.readTextFile(
    new URL(
      "../../migrations/20260822210000_calendar_integrations.sql",
      import.meta.url,
    ),
  );
  const edge = await Deno.readTextFile(
    new URL("../calendar-integrations/index.ts", import.meta.url),
  );
  assertStringIncludes(edge, "queueInitialHomePlateSources");
  assertStringIncludes(edge, "source_kind: definition.table");
  assertStringIncludes(edge, 'operation: "upsert"');
  assertStringIncludes(migration, "when tg_op = 'DELETE' then 'deleted'");
  assertStringIncludes(migration, "after insert or delete or update of");
  assertStringIncludes(migration, "coalesce(new.id, old.id)");
});
