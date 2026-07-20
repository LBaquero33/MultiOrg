import {
  materializeOccurrences,
  notificationIntent,
  requiredCapability,
  resolveScheduleReadAuthority,
  sanitizeEventForConsumer,
  validateRecurrence,
} from "./team_scheduling.ts";

function assert(condition: boolean, message: string) {
  if (!condition) throw new Error(message);
}

const migrationURL = new URL(
  "../../migrations/20260717183000_unified_team_scheduling.sql",
  import.meta.url,
);

Deno.test("daily recurrence is deterministic and bounded", () => {
  const rows = materializeOccurrences(
    "2027-01-04T20:00:00.000Z",
    "2027-01-04T22:00:00.000Z",
    { frequency: "daily", interval: 2, occurrenceCount: 3 },
  );
  assert(rows.length === 3, "count");
  assert(rows[1].startAt === "2027-01-06T20:00:00.000Z", "interval");
  assert(rows[2].index === 2, "stable index");
});

Deno.test("weekly selected weekdays materialize without opaque rules", () => {
  const rows = materializeOccurrences(
    "2027-01-04T20:00:00.000Z",
    "2027-01-04T22:00:00.000Z",
    { frequency: "weekly", interval: 1, weekdays: [1, 3], occurrenceCount: 4 },
  );
  assert(
    rows.map((row) => row.startAt.slice(0, 10)).join(",") ===
      "2027-01-04,2027-01-06,2027-01-11,2027-01-13",
    "weekdays",
  );
});

Deno.test("recurrence end date is inclusive and deterministic", () => {
  const rows = materializeOccurrences(
    "2027-01-04T20:00:00.000Z",
    "2027-01-04T22:00:00.000Z",
    { frequency: "daily", interval: 2, endsOn: "2027-01-08" },
  );
  assert(
    rows.map((row) => row.startAt.slice(0, 10)).join(",") ===
      "2027-01-04,2027-01-06,2027-01-08",
    "inclusive recurrence end",
  );
});

Deno.test("recurrence rejects ambiguous and unbounded invalid inputs", () => {
  assert(
    validateRecurrence({ frequency: "daily", interval: 0 }) ===
      "invalid_recurrence_interval",
    "interval",
  );
  assert(
    validateRecurrence({ frequency: "weekly", interval: 1, weekdays: [] }) ===
      "invalid_recurrence_weekdays",
    "weekdays",
  );
  assert(
    validateRecurrence({
      frequency: "daily",
      interval: 1,
      endsOn: "2027-01-10",
      occurrenceCount: 3,
    }) === "ambiguous_recurrence_end",
    "end contract",
  );
});

Deno.test("consumer event shape cannot expose coach-private fields", () => {
  const safe = sanitizeEventForConsumer({
    id: "event",
    title: "Practice",
    notes: "private",
    metadata: { secret: true },
  });
  assert(!("notes" in safe), "notes removed");
  assert(!("metadata" in safe), "metadata removed");
  assert(safe.title === "Practice", "public details retained");
});

Deno.test("subtype authorization uses scheduling capabilities", () => {
  assert(
    requiredCapability("practice") === "manage_practice_event",
    "practice",
  );
  assert(requiredCapability("game") === "manage_game_event", "game");
  assert(
    requiredCapability("custom") === null,
    "custom uses common create capability",
  );
});

Deno.test("schedule read authority keeps organization and coach paths separate", () => {
  for (const role of ["owner", "admin"]) {
    assert(
      resolveScheduleReadAuthority(role, []).allowed,
      `${role} does not require coach assignment`,
    );
  }
  assert(
    resolveScheduleReadAuthority("coach", ["view_team_schedule"]).allowed,
    "assigned capable coach",
  );
  for (
    const role of ["coach", "read_only", "player", "parent", "platform_admin"]
  ) {
    assert(
      !resolveScheduleReadAuthority(role, []).allowed,
      `${role} requires its explicit read path`,
    );
  }
});

Deno.test("notification intent changes are deterministic and never dispatch", () => {
  assert(
    notificationIntent(null, { status: "scheduled" }) === "new_event",
    "publish",
  );
  assert(
    notificationIntent({ status: "scheduled" }, { status: "cancelled" }) ===
      "cancellation",
    "cancel",
  );
  assert(
    notificationIntent({ status: "scheduled", start_at: "a" }, {
      status: "scheduled",
      start_at: "b",
    }) === "time_change",
    "time",
  );
});

Deno.test("migration is normalized additive indexed RLS and auditable", async () => {
  const sql = await Deno.readTextFile(migrationURL);
  for (
    const table of [
      "sd_team_events",
      "sd_team_event_series",
      "sd_team_event_practices",
      "sd_team_event_games",
      "sd_team_event_tournaments",
      "sd_team_event_meetings",
      "sd_team_event_travel",
    ]
  ) {
    assert(sql.includes(`create table if not exists public.${table}`), table);
  }
  assert(sql.includes("team_event_scope_mismatch"), "scope invariant");
  assert(
    sql.includes("arrival_at is null or arrival_at <= start_at"),
    "arrival invariant",
  );
  assert(sql.includes("status <> 'cancelled'"), "cancelled conflict exclusion");
  assert(
    sql.includes("sd_facility_bookings booking"),
    "legacy facility compatibility",
  );
  assert(
    sql.includes("sd_team_event_notification_intents"),
    "notification intents",
  );
  assert(sql.match(/enable row level security/g)?.length === 10, "RLS");
  assert(!sql.includes("drop table"), "additive");
});

Deno.test("Phase 12A resolver remains the single scheduling capability authority", async () => {
  const sql = await Deno.readTextFile(migrationURL);
  assert(
    sql.includes(
      "create or replace function public.sd_resolve_team_capabilities",
    ),
    "same resolver",
  );
  assert(
    sql.includes("responsibility in ('head_coach','team_manager')"),
    "parity",
  );
  assert(
    sql.includes("responsibility = 'assistant_coach'"),
    "assistant centralized",
  );
  assert(
    sql.includes(
      "'view_team_schedule','create_team_event','edit_team_event','cancel_team_event'",
    ),
    "capabilities",
  );
});

Deno.test("edge authorization precedes scheduling mutations", async () => {
  const source = await Deno.readTextFile(
    new URL("../team-scheduling/index.ts", import.meta.url),
  );
  const resolver = source.indexOf('rpc("sd_resolve_team_capabilities"');
  const mutation = source.indexOf('from("sd_team_events").insert');
  assert(resolver > 0 && mutation > resolver, "resolver before mutation");
  assert(
    source.includes("return fail(403, `${needed}_required`)"),
    "view-only rejection",
  );
  assert(
    source.includes('eq("visibility", "team").neq("status", "draft")'),
    "consumer visibility",
  );
  assert(
    source.includes('query.eq("season_id", requestedSeason)'),
    "admin season filtering",
  );
  for (
    const code of [
      "season_missing",
      "season_inactive",
      "team_missing",
      "team_archived",
      "stale_team_context",
      "permission_denied",
      "service_unavailable",
    ]
  ) {
    assert(source.includes(`"${code}"`), `controlled ${code}`);
  }
  assert(source.includes("schema_version: 1"), "versioned envelope");
  assert(source.includes("request_id:"), "request correlation");
  assert(!source.includes("error.message"), "no raw provider errors");
  assert(
    source.includes('action === "update_future"'),
    "future occurrence edit",
  );
  assert(
    source.includes("occurrences.slice(1)"),
    "every recurrence is conflict checked",
  );
  assert(
    source.includes("futureIds.has"),
    "future edits exclude their replaced rows",
  );
  assert(source.includes('action === "cancel_series"'), "series cancellation");
  assert(
    source.includes("sd_team_event_notification_intents"),
    "intent persistence",
  );
  assert(!source.includes("sd_notifications"), "no notification dispatch");
});
