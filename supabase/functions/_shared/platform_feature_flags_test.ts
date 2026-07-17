import {
  platformFeatureEnabled,
  platformFeatureFlagMutation,
  PLAYER_DEVELOPMENT_COPILOT_FEATURE_KEY,
} from "./platform_feature_flags.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

Deno.test("Player Development Copilot platform feature defaults off", () => {
  assert(!platformFeatureEnabled(null), "missing row fails closed");
  assert(!platformFeatureEnabled({}), "missing enabled value fails closed");
  assert(!platformFeatureEnabled({ enabled: false }), "false remains disabled");
  assert(
    platformFeatureEnabled({ enabled: true }),
    "only true enables feature",
  );
});

Deno.test("platform feature mutation accepts only the supported audited toggle", () => {
  const parsed = platformFeatureFlagMutation({
    key: PLAYER_DEVELOPMENT_COPILOT_FEATURE_KEY,
    enabled: true,
    request_id: "11111111-1111-4111-8111-111111111111",
  }, true);
  assert(parsed?.enabled === true, "authorized toggle parsed");
  assert(parsed?.key === PLAYER_DEVELOPMENT_COPILOT_FEATURE_KEY, "key stable");
});

Deno.test("non-platform administrators and malformed feature mutations fail closed", () => {
  const body = {
    key: PLAYER_DEVELOPMENT_COPILOT_FEATURE_KEY,
    enabled: true,
    request_id: "11111111-1111-4111-8111-111111111111",
  };
  assert(platformFeatureFlagMutation(body, false) === null, "non-admin denied");
  assert(
    platformFeatureFlagMutation({ ...body, key: "another_feature" }, true) ===
      null,
    "unknown feature denied",
  );
  assert(
    platformFeatureFlagMutation({ ...body, enabled: "true" }, true) === null,
    "non-boolean state denied",
  );
  assert(
    platformFeatureFlagMutation({ ...body, request_id: "retry" }, true) ===
      null,
    "idempotency key required",
  );
});

Deno.test("feature migration is additive, default-off, readable, audited, and service-role mutable only", async () => {
  const sql = (await Deno.readTextFile(
    new URL(
      "../../migrations/20260717153000_player_development_copilot_feature_flag.sql",
      import.meta.url,
    ),
  )).toLowerCase();
  assert(
    sql.includes("create table if not exists public.sd_platform_feature_flags"),
    "migration is additive",
  );
  assert(
    sql.includes("'player_development_copilot',\n  false"),
    "feature defaults off",
  );
  assert(sql.includes("enable row level security"), "RLS enabled");
  assert(
    sql.includes("for select\n  to authenticated\n  using (true)"),
    "authenticated clients receive read-only state",
  );
  assert(
    sql.includes(
      "revoke all on table public.sd_platform_feature_flags\n  from public, anon, authenticated",
    ),
    "untrusted mutation rights revoked",
  );
  assert(
    sql.includes("from public.sd_platform_admins administrator"),
    "setter verifies platform admin entitlement",
  );
  assert(
    sql.includes("insert into public.sd_platform_audit_logs"),
    "every mutation is audited in the same transaction",
  );
  assert(
    sql.includes(
      "grant execute on function public.sd_set_platform_feature_flag",
    ) &&
      sql.includes("to service_role"),
    "only service role can invoke the setter",
  );
  assert(
    !/\b(delete|truncate)\s+from\s+public\.sd_development_/i.test(sql),
    "AI history is preserved",
  );
});

Deno.test("platform admin endpoint authorizes before feature listing or mutation", async () => {
  const source = await Deno.readTextFile(
    new URL("../platform_admin/index.ts", import.meta.url),
  );
  const authorization = source.indexOf("canAccessPlatformAdministration");
  const list = source.indexOf('action === "list_platform_feature_flags"');
  const update = source.indexOf('action === "update_platform_feature_flag"');
  assert(
    authorization >= 0 && authorization < list,
    "authorization precedes list",
  );
  assert(authorization < update, "authorization precedes mutation");
  assert(
    source.includes("sd_set_platform_feature_flag"),
    "audited setter RPC used",
  );
});
