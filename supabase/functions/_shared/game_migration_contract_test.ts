import { assert, assertEquals } from "jsr:@std/assert@1";

const canonicalCategories = [
  "payment_request_created",
  "payment_received",
  "booking_created",
  "booking_updated",
  "program_assigned",
  "program_updated",
  "message_received",
  "testing_result_added",
  "organization_announcement",
  "team_announcement",
  "event_announcement",
  "schedule_change",
  "event_reminder",
  "attendance",
  "availability",
  "practice_plan",
  "game_plan",
  "lineup_assignment",
  "registration",
  "payment_notice",
  "result_recap",
  "event_created",
  "event_updated",
  "event_canceled",
  "event_postponed",
  "event_rescheduled",
  "availability_requested",
  "game_starting",
  "game_live",
  "game_final",
  "game_update",
  "system",
] as const;

const categoryConstraintMigrations = [
  {
    path: "../../migrations/20260729020000_game_calendar_integration.sql",
    categories: canonicalCategories.filter((category) =>
      category !== "game_update"
    ),
  },
  {
    path: "../../migrations/20260729070000_game_finalization_and_audit.sql",
    categories: canonicalCategories,
  },
  {
    path:
      "../../migrations/20260729090000_restore_game_calendar_notification_categories.sql",
    categories: canonicalCategories,
  },
] as const;

async function read(relativePath: string): Promise<string> {
  return await Deno.readTextFile(new URL(relativePath, import.meta.url));
}

Deno.test("pending game migrations preserve the complete notification category contract", async () => {
  for (const { path, categories } of categoryConstraintMigrations) {
    const migration = await read(path);
    for (const category of categories) {
      assert(
        migration.includes(`'${category}'`),
        `${path} must preserve ${category}`,
      );
    }
    assert(migration.includes("not valid"));
    assert(
      migration.includes(
        "validate constraint sd_notifications_category_check",
      ),
    );
  }
});

Deno.test("central notification validation accepts the same canonical categories", async () => {
  const migration = await read(
    "../../migrations/20260729100000_align_game_notification_validation.sql",
  );
  const missing = canonicalCategories.filter((category) =>
    !migration.includes(`'${category}'`)
  );
  assertEquals(missing, []);
});

Deno.test("calendar migration preserves legacy sources while adding event source", async () => {
  const migration = await read(
    "../../migrations/20260729020000_game_calendar_integration.sql",
  );
  const sources = [
    "payment_request",
    "payment_webhook",
    "announcement",
    "chat",
    "schedule",
    "event_operation",
    "practice_plan",
    "game_plan",
    "registration",
    "organization_finance",
    "event",
    "system",
  ];

  for (const source of sources) {
    assert(migration.includes(`'${source}'`), `missing source ${source}`);
  }
  assert(
    migration.includes("validate constraint sd_notifications_source_check"),
  );
});
