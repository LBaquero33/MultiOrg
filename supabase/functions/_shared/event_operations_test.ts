import {
  completionBlockers,
  isNearEventStart,
  mayTransition,
  operationPrimaryAction,
  operationTypeForEvent,
  sanitizeOperationForConsumer,
  sanitizeParticipantForConsumer,
} from "./event_operations.ts";

function assert(condition: boolean, message: string) {
  if (!condition) throw new Error(message);
}

const migrationURL = new URL(
  "../../migrations/20260717200000_baseball_day_operations.sql",
  import.meta.url,
);
const edgeURL = new URL("../event-operations/index.ts", import.meta.url);

Deno.test("event types map to the six canonical day modes", () => {
  assert(operationTypeForEvent("practice") === "practice_day", "practice");
  assert(operationTypeForEvent("game") === "game_day", "game");
  assert(
    operationTypeForEvent("tournament") === "tournament_day",
    "tournament",
  );
  assert(operationTypeForEvent("meeting") === "meeting_day", "meeting");
  assert(operationTypeForEvent("travel") === "travel_day", "travel");
  assert(operationTypeForEvent("custom") === "general_event_day", "general");
});

Deno.test("operation transitions and primary actions are deterministic", () => {
  assert(mayTransition("not_started", "ready"), "prepare");
  assert(mayTransition("ready", "in_progress"), "start");
  assert(mayTransition("in_progress", "paused"), "pause");
  assert(mayTransition("paused", "in_progress"), "resume");
  assert(mayTransition("completed", "ready"), "reopen");
  assert(!mayTransition("completed", "in_progress"), "cannot skip reopen");
  assert(
    operationPrimaryAction("ready", "game_day") === "Start Game Day",
    "does not imply scorekeeping",
  );
  assert(
    operationPrimaryAction("ready", "practice_day") === "Start Practice",
    "practice",
  );
});

Deno.test("completion blockers keep attendance and checklist independent", () => {
  const blockers = completionBlockers(
    [
      {
        expected: true,
        participant_type: "player",
        attendance_status: "not_recorded",
      },
      {
        expected: true,
        participant_type: "coach",
        attendance_status: "not_recorded",
      },
      {
        expected: true,
        participant_type: "player",
        attendance_status: "present",
      },
    ],
    [
      { required: true, completed_at: null, overridden_at: null },
      { required: true, completed_at: "now", overridden_at: null },
      { required: false, completed_at: null, overridden_at: null },
    ],
  );
  assert(blockers.attendance === 1, "only expected players block attendance");
  assert(blockers.requiredChecklist === 1, "only unresolved required items");
});

Deno.test("consumer redaction removes every private operation field", () => {
  const participant = sanitizeParticipantForConsumer({
    user_id: "player",
    availability_status: "late",
    availability_reason: "private reason",
    attendance_notes: "private attendance",
    private_notes: "staff only",
    checked_in_by: "coach",
  });
  assert(
    participant.availability_reason === "private reason",
    "own availability reason retained",
  );
  assert(!("attendance_notes" in participant), "attendance note removed");
  assert(!("private_notes" in participant), "private note removed");
  assert(!("checked_in_by" in participant), "actor removed");
  assert(participant.availability_status === "late", "status retained");
  const operation = sanitizeOperationForConsumer({
    id: "operation",
    internal_notes: "private",
    operational_summary: "visible recap",
  });
  assert(!("internal_notes" in operation), "internal operation note removed");
  assert(operation.operational_summary === "visible recap", "summary retained");
});

Deno.test("near-start availability attention is bounded", () => {
  const now = new Date("2027-01-04T12:00:00.000Z");
  assert(isNearEventStart("2027-01-05T11:00:00.000Z", now), "within 24h");
  assert(isNearEventStart("2027-01-04T07:00:00.000Z", now), "recent start");
  assert(!isNearEventStart("2027-01-06T12:00:00.000Z", now), "too early");
  assert(!isNearEventStart("2027-01-04T05:00:00.000Z", now), "too late");
});

Deno.test("migration is additive normalized indexed and server-only", async () => {
  const sql = await Deno.readTextFile(migrationURL);
  for (
    const table of [
      "sd_event_operations",
      "sd_event_operation_participants",
      "sd_event_operation_checklist_items",
      "sd_event_operation_notes",
      "sd_event_operation_versions",
      "sd_event_operation_audit_logs",
      "sd_event_operation_mutations",
    ]
  ) {
    assert(sql.includes(`create table if not exists public.${table}`), table);
    assert(
      sql.includes(`alter table public.${table} enable row level security`),
      `${table} RLS`,
    );
  }
  assert(sql.includes("unique (event_id)"), "one operation per event");
  assert(
    sql.includes("unique (event_operation_id, user_id)"),
    "participant snapshot identity",
  );
  assert(sql.includes("availability_status text"), "availability separate");
  assert(sql.includes("attendance_status text"), "attendance separate");
  assert(
    sql.includes("sd_team_event_notification_intents_operation_scope_fk"),
    "intent link",
  );
  assert(sql.includes("grant select, insert, update, delete"), "service grant");
  assert(!sql.includes("drop table"), "non-destructive");
});

Deno.test("central resolver owns all Phase 12C responsibility mappings", async () => {
  const sql = await Deno.readTextFile(migrationURL);
  for (
    const capability of [
      "view_event_operation",
      "start_event_operation",
      "manage_event_attendance",
      "manage_event_availability",
      "manage_event_checklist",
      "add_team_event_notes",
      "add_private_player_notes",
      "complete_event_operation",
      "reopen_event_operation",
    ]
  ) assert(sql.includes(`'${capability}'`), capability);
  assert(
    sql.includes("responsibility in ('head_coach','team_manager')"),
    "parity",
  );
  assert(
    sql.includes("responsibility = 'assistant_coach'"),
    "assistant policy",
  );
  assert(sql.includes("responsibility = 'read_only'"), "read-only policy");
});

Deno.test("edge initialization is repairable idempotent and snapshots participants", async () => {
  const source = await Deno.readTextFile(edgeURL);
  assert(
    source.includes('.eq("event_id", event.id).maybeSingle()'),
    "existing lookup",
  );
  assert(source.includes('error?.code === "23505"'), "concurrent initialize");
  assert(
    source.includes('onConflict: "event_operation_id,user_id"'),
    "participant upsert",
  );
  assert(
    source.includes('onConflict: "event_operation_id,source,title"'),
    "checklist upsert",
  );
  assert(
    source.includes('action === "reconcile_participants"'),
    "roster reconciliation",
  );
  assert(source.includes('"participants_reconciled"'), "reconciliation audit");
});

Deno.test("edge authorization fails closed across organization team and household", async () => {
  const source = await Deno.readTextFile(edgeURL);
  const membership = source.indexOf('from(\n    "sd_org_memberships"');
  const event = source.indexOf('from("sd_team_events")');
  assert(
    membership > 0 && event > membership,
    "membership before event access",
  );
  assert(
    source.includes('rpc("sd_resolve_team_capabilities"'),
    "central resolver",
  );
  assert(source.includes('"view_event_operation_required"'), "read-only gate");
  assert(source.includes('"parent_link_required"'), "parent link gate");
  assert(source.includes('"player_scope_required"'), "player self gate");
  assert(
    source.includes('event.visibility !== "team"'),
    "consumer visibility gate",
  );
  assert(
    source.includes('"team_id",\n        event.team_id,') &&
      source.includes('"active_team_required"'),
    "active team scope",
  );
});

Deno.test("availability attendance and completion enforce versions and reasons", async () => {
  const source = await Deno.readTextFile(edgeURL);
  assert(
    source.includes('"availability_override_reason_required"'),
    "coach override reason",
  );
  assert(source.includes('"stale_version"'), "optimistic concurrency");
  assert(source.includes('action === "attendance_bulk"'), "bulk attendance");
  assert(
    source.includes('"attendance_correction_reason_required"'),
    "correction reason",
  );
  assert(
    source.includes('action === "finalize_attendance"'),
    "attendance finalization",
  );
  assert(
    source.includes('"ready_completion_reason_required"'),
    "ready completion reason",
  );
  assert(source.includes('"reopen_reason_required"'), "reopen reason");
  assert(source.includes('status: "completed"'), "canonical event completion");
});

Deno.test("notes and response payloads enforce role-aware privacy", async () => {
  const source = await Deno.readTextFile(edgeURL);
  assert(
    source.includes("sanitizeParticipantForConsumer(participant)"),
    "participant redaction",
  );
  assert(
    source.includes("sanitizeOperationForConsumer(operation)"),
    "operation redaction",
  );
  assert(source.includes('item.visibility === "team"'), "checklist redaction");
  assert(source.includes('note.visibility === "team"'), "note redaction");
  assert(
    source.includes('"private_note_visibility_required"'),
    "staff note invariant",
  );
  assert(
    source.includes('"player_note_visibility_required"'),
    "player note privacy",
  );
  assert(source.includes('"invalid_note_type"'), "note type allowlist");
  assert(
    source.includes('.eq("participant_type", "player")'),
    "player-note subject scope",
  );
});

Deno.test("mutations audits and notification intents are retry deterministic", async () => {
  const source = await Deno.readTextFile(edgeURL);
  const sql = await Deno.readTextFile(migrationURL);
  assert(
    source.includes('rpc(\n      "sd_apply_event_operation_mutation"'),
    "transactional RPC boundary",
  );
  assert(
    sql.includes("v_receipt.request_fingerprint <> v_fingerprint"),
    "actor event action and payload binding",
  );
  assert(
    sql.includes("return v_receipt.response ||") &&
      sql.includes("'replayed', true"),
    "canonical receipt replay",
  );
  assert(sql.includes("for update of participant"), "bulk lock");
  assert(
    sql.includes("input.expected_version = participant.version"),
    "bulk versions",
  );
  assert(sql.includes("'operation_started'"), "start intent");
  assert(sql.includes("'event_completed'"), "completion intent");
  assert(sql.includes("'attendance_correction'"), "correction intent");
  assert(
    !source.includes('from("sd_notifications")'),
    "no notification dispatch",
  );
});
