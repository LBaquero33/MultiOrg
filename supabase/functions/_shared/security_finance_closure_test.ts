import {
  assert,
  assertEquals,
  assertFalse,
  assertStringIncludes,
} from "jsr:@std/assert@1";

const migrationURL = new URL(
  "../../migrations/20260822050000_security_finance_analytics_closure.sql",
  import.meta.url,
);

const legacyTables = [
  "attendance",
  "conversation_participants",
  "conversations",
  "device_tokens",
  "event_participants",
  "events",
  "facilities",
  "facility_bookings",
  "facility_resources",
  "invitations",
  "memberships",
  "messages",
  "notifications",
  "organizations",
  "parent_child_links",
  "password_reset_tokens",
  "player_profiles",
  "program_assignments",
  "program_completions",
  "program_days",
  "program_exercises",
  "programs",
  "seasons",
  "team_members",
  "teams",
  "testing_categories",
  "testing_results",
  "testing_sessions",
  "users",
];

Deno.test("legacy public tables are retired without destructive data changes", async () => {
  const sql = await Deno.readTextFile(migrationURL);

  for (const table of legacyTables) {
    assertStringIncludes(sql, `'${table}'`);
  }
  assertStringIncludes(sql, "enable row level security");
  assertStringIncludes(
    sql,
    "revoke all on table public.%I from anon, authenticated",
  );
  assertFalse(/drop\s+table/i.test(sql));
  assertFalse(/truncate\s+/i.test(sql));
  assertFalse(/delete\s+from\s+public\./i.test(sql));
});

Deno.test("expense categories are organization scoped and history safe", async () => {
  const sql = await Deno.readTextFile(migrationURL);

  assertStringIncludes(
    sql,
    "create table if not exists public.sd_expense_categories",
  );
  assertStringIncludes(sql, "unique (org_id, normalized_name)");
  assertStringIncludes(sql, "public.sd_is_org_admin(org_id)");
  assertStringIncludes(sql, "add column if not exists category_id uuid");
  assertStringIncludes(sql, "on delete set null");
  assertStringIncludes(
    sql,
    "revoke delete on public.sd_expense_categories from anon, authenticated",
  );
  assertEquals((sql.match(/public\.sd_is_org_admin/g) ?? []).length >= 8, true);
  assertFalse(/using\s*\(\s*true\s*\)/i.test(sql));
  assertFalse(/with\s+check\s*\(\s*true\s*\)/i.test(sql));
});

Deno.test("expense receipts remain private and organization authorized", async () => {
  const sql = await Deno.readTextFile(migrationURL);

  assertStringIncludes(sql, "'organization-expense-receipts'");
  assertStringIncludes(sql, "false,\n  20971520");
  assertStringIncludes(sql, "bucket_id = 'organization-expense-receipts'");
  assertStringIncludes(sql, "owner_id = (select auth.uid()::text)");
  assertStringIncludes(
    sql,
    "public.sd_is_org_admin(((storage.foldername(name))[1])::uuid)",
  );
  assert(/for insert to authenticated/i.test(sql));
  assert(/for select to authenticated/i.test(sql));
  assert(/for update to authenticated/i.test(sql));
  assert(/for delete to authenticated/i.test(sql));
});
