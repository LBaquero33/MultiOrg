import {
  createClient,
  type SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  type AnalyticsDiscipline,
  type AnalyticsFilters,
  type AnalyticsRequest,
  canAccessPlayer,
  normalizedFilters,
  normalizedUuid,
  stableStringify,
  validModule,
} from "./contract.ts";

const env = (name: string) => (Deno.env.get(name) ?? "").trim();
const supabaseUrl = env("SUPABASE_URL") || env("DHD_SUPABASE_URL");
const anonKey = env("SUPABASE_ANON_KEY") || env("DHD_SUPABASE_ANON_KEY");
const serviceKey = env("DHD_SERVICE_ROLE_KEY") ||
  env("SUPABASE_SERVICE_ROLE_KEY");
const analyticsUrl = env("HOME_PLATE_ANALYTICS_URL").replace(/\/$/, "");
const analyticsSecret = env("HOME_PLATE_ANALYTICS_HMAC_SECRET");

const corsHeaders = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, apikey, content-type",
  "access-control-allow-methods": "POST, OPTIONS",
};

type Row = Record<string, unknown>;

class AnalyticsError extends Error {
  constructor(readonly code: string, readonly status = 400) {
    super(code);
  }
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "content-type": "application/json",
      "cache-control": "no-store",
    },
  });
}

function stringValue(value: unknown): string | null {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

function boolValue(value: unknown): boolean {
  return value === true;
}

function rows(value: unknown): Row[] {
  return Array.isArray(value)
    ? value.filter((item): item is Row => !!item && typeof item === "object")
    : [];
}

async function queryRows(
  query: PromiseLike<{ data: unknown; error: { message?: string } | null }>,
  code: string,
): Promise<Row[]> {
  const { data, error } = await query;
  if (error) throw new AnalyticsError(code, 500);
  return rows(data);
}

async function authenticate(
  request: Request,
): Promise<{ admin: SupabaseClient; actorId: string }> {
  if (!supabaseUrl || !anonKey || !serviceKey) {
    throw new AnalyticsError("analytics_gateway_not_configured", 500);
  }
  const authorization = request.headers.get("authorization") ?? "";
  if (!authorization.toLowerCase().startsWith("bearer ")) {
    throw new AnalyticsError("not_authenticated", 401);
  }
  const caller = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await caller.auth.getUser();
  const actorId = normalizedUuid(data.user?.id);
  if (error || !actorId) throw new AnalyticsError("not_authenticated", 401);
  return {
    actorId,
    admin: createClient(supabaseUrl, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    }),
  };
}

async function authorizeOrganization(
  admin: SupabaseClient,
  actorId: string,
  orgId: string,
): Promise<string> {
  const { data, error } = await admin.from("sd_org_memberships")
    .select("role,status").eq("org_id", orgId).eq("user_id", actorId)
    .maybeSingle();
  if (error) throw new AnalyticsError("membership_lookup_failed", 500);
  const role = stringValue(data?.role)?.toLowerCase();
  const status = stringValue(data?.status)?.toLowerCase();
  if (!role || status !== "active") {
    throw new AnalyticsError("organization_membership_required", 403);
  }
  return role;
}

async function authorizePlayer(
  admin: SupabaseClient,
  actorId: string,
  orgId: string,
  playerId: string,
): Promise<void> {
  const role = await authorizeOrganization(admin, actorId, orgId);
  const { data: playerMembership, error: playerError } = await admin.from(
    "sd_org_memberships",
  ).select("user_id").eq("org_id", orgId).eq("user_id", playerId)
    .eq("role", "player").eq("status", "active").maybeSingle();
  if (playerError) throw new AnalyticsError("player_lookup_failed", 500);
  if (!playerMembership) throw new AnalyticsError("player_not_found", 404);

  const [playerRosters, coachAssignments, parentLinks] = await Promise.all([
    queryRows(
      admin.from("sd_player_team_memberships").select("team_id")
        .eq("organization_id", orgId).eq("player_id", playerId)
        .eq("active", true).is("ended_at", null),
      "player_team_scope_lookup_failed",
    ),
    role === "coach"
      ? queryRows(
        admin.from("sd_coach_team_assignments")
          .select("team_id,organization_wide_access")
          .eq("organization_id", orgId).eq("coach_id", actorId)
          .eq("active", true).is("ended_at", null),
        "coach_team_scope_lookup_failed",
      )
      : Promise.resolve([]),
    role === "parent"
      ? queryRows(
        admin.from("sd_parent_child_links").select("child_id")
          .eq("org_id", orgId).eq("parent_id", actorId),
        "parent_child_scope_lookup_failed",
      )
      : Promise.resolve([]),
  ]);
  const playerTeamIds = new Set(
    playerRosters.map((row) => stringValue(row.team_id)).filter((value): value is string => !!value),
  );
  const coachTeamIds = new Set(
    coachAssignments.map((row) => stringValue(row.team_id)).filter((value): value is string => !!value),
  );
  const linkedChildIds = new Set(
    parentLinks.map((row) => stringValue(row.child_id)).filter((value): value is string => !!value),
  );
  const organizationWide = coachAssignments.some((row) =>
    boolValue(row.organization_wide_access)
  );
  if (
    !canAccessPlayer(
      role,
      actorId,
      playerId,
      linkedChildIds,
      coachTeamIds,
      playerTeamIds,
      organizationWide,
    )
  ) {
    throw new AnalyticsError("player_not_authorized", 403);
  }
}

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return [...new Uint8Array(digest)].map((byte) =>
    byte.toString(16).padStart(2, "0")
  ).join("");
}

async function serviceHeaders(body: string): Promise<Record<string, string>> {
  if (!analyticsSecret) {
    throw new AnalyticsError("analytics_service_not_configured", 503);
  }
  const timestamp = Math.floor(Date.now() / 1000).toString();
  const nonce = crypto.randomUUID().replaceAll("-", "");
  const bodyHash = await sha256(body);
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(analyticsSecret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(`${timestamp}.${nonce}.${bodyHash}`),
  );
  const signatureHex = [...new Uint8Array(signature)].map((byte) =>
    byte.toString(16).padStart(2, "0")
  ).join("");
  return {
    "content-type": "application/json",
    "x-home-plate-timestamp": timestamp,
    "x-home-plate-nonce": nonce,
    "x-home-plate-signature": signatureHex,
  };
}

async function callAnalytics(
  path: string,
  method: "GET" | "POST",
  payload?: Record<string, unknown>,
): Promise<unknown> {
  if (!analyticsUrl || !analyticsSecret) {
    throw new AnalyticsError("analytics_service_not_configured", 503);
  }
  const body = payload ? JSON.stringify(payload) : "";
  let response: Response;
  try {
    response = await fetch(`${analyticsUrl}${path}`, {
      method,
      headers: await serviceHeaders(body),
      body: method === "POST" ? body : undefined,
      signal: AbortSignal.timeout(20_000),
    });
  } catch {
    throw new AnalyticsError("analytics_service_unavailable", 503);
  }
  const responseBody = await response.json().catch(() => null);
  if (!response.ok) {
    const safeCode = responseBody && typeof responseBody === "object"
      ? stringValue((responseBody as Row).error)
      : null;
    throw new AnalyticsError(safeCode ?? "analysis_failed", response.status);
  }
  return responseBody;
}

async function resolveImport(
  admin: SupabaseClient,
  orgId: string,
  playerId: string,
  requestedId: string | null,
  requestedProvider: string | null,
): Promise<Row> {
  let query = admin.from("sd_development_import_jobs").select(
    "id,provider,status,original_file_type,file_sha256,storage_bucket,storage_path,completed_at,created_at",
  ).eq("org_id", orgId).eq("player_id", playerId)
    .in("status", ["completed", "completed_with_errors"])
    .not("storage_bucket", "is", null).not("storage_path", "is", null);
  if (requestedId) query = query.eq("id", requestedId);
  if (requestedProvider) query = query.eq("provider", requestedProvider);
  const { data, error } = await query.order("completed_at", { ascending: false })
    .order("created_at", { ascending: false }).limit(1);
  if (error) throw new AnalyticsError("analytics_source_lookup_failed", 500);
  const job = rows(data)[0];
  if (!job) throw new AnalyticsError("analytics_source_not_found", 404);
  if (
    stringValue(job.storage_bucket) !== "player-development-imports" ||
    !stringValue(job.storage_path) || !stringValue(job.file_sha256)
  ) {
    throw new AnalyticsError("analytics_source_invalid", 422);
  }
  return job;
}

async function listSources(
  admin: SupabaseClient,
  orgId: string,
  playerId: string,
): Promise<Row[]> {
  const { data, error } = await admin.from("sd_development_import_jobs").select(
    "id,provider,file_name,row_count,completed_at",
  ).eq("org_id", orgId).eq("player_id", playerId)
    .in("status", ["completed", "completed_with_errors"])
    .in("provider", ["trackman", "hittrax", "rapsodo"])
    .not("storage_bucket", "is", null).not("storage_path", "is", null)
    .order("completed_at", { ascending: false }).limit(100);
  if (error) throw new AnalyticsError("analytics_source_lookup_failed", 500);
  return rows(data).map((source) => ({
    id: stringValue(source.id),
    provider: stringValue(source.provider) ?? "generic_csv",
    file_name: stringValue(source.file_name) ?? "Imported data",
    row_count: typeof source.row_count === "number" ? source.row_count : 0,
    completed_at: stringValue(source.completed_at),
  })).filter((source) => source.id && source.completed_at);
}

async function analysisPayload(
  admin: SupabaseClient,
  request: AnalyticsRequest,
  orgId: string,
  playerId: string,
): Promise<{ cacheKey: string; payload: Record<string, unknown> }> {
  const discipline = request.discipline;
  if (!discipline || !validModule(discipline, request.module)) {
    throw new AnalyticsError("invalid_analytics_module", 400);
  }
  const requestedJobId = request.import_job_id
    ? normalizedUuid(request.import_job_id)
    : null;
  if (request.import_job_id && !requestedJobId) {
    throw new AnalyticsError("invalid_import_job_id", 400);
  }
  const provider = stringValue(request.provider)?.toLowerCase() ?? null;
  const job = await resolveImport(
    admin,
    orgId,
    playerId,
    requestedJobId,
    provider,
  );
  const bucket = stringValue(job.storage_bucket)!;
  const objectPath = stringValue(job.storage_path)!;
  const { data: signed, error: signError } = await admin.storage.from(bucket)
    .createSignedUrl(objectPath, 120);
  if (signError || !signed?.signedUrl) {
    throw new AnalyticsError("analytics_source_signing_failed", 500);
  }
  const filters: AnalyticsFilters = normalizedFilters(request.filters);
  const cacheMaterial = stableStringify({
    source: stringValue(job.file_sha256),
    player: playerId,
    discipline,
    module: request.module,
    provider: stringValue(job.provider) ?? "trackman",
    filters,
    model_version: "homeplate-r-analytics.v1",
    benchmark_version: "homeplate-trackman-age-bands.v1",
  });
  const cacheKey = await sha256(cacheMaterial);
  return {
    cacheKey,
    payload: {
      source_url: signed.signedUrl,
      file_type: stringValue(job.original_file_type) ?? "csv",
      provider: stringValue(job.provider) ?? "trackman",
      discipline,
      module: request.module,
      filters,
      cache_key: cacheKey,
      benchmark_summary: { status: "building" },
    },
  };
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }
  try {
    const body = await request.json() as AnalyticsRequest;
    const orgId = normalizedUuid(body.org_id);
    if (!orgId) throw new AnalyticsError("invalid_org_id", 400);
    const { admin, actorId } = await authenticate(request);
    const action = body.action ?? "run_analysis";
    if (action === "get_catalog") {
      await authorizeOrganization(admin, actorId, orgId);
      return json(await callAnalytics("/v1/catalog", "GET"));
    }
    const playerId = normalizedUuid(body.player_id);
    if (!playerId) throw new AnalyticsError("invalid_player_id", 400);
    await authorizePlayer(admin, actorId, orgId, playerId);
    if (action === "list_sources") {
      return json({ sources: await listSources(admin, orgId, playerId) });
    }
    const { cacheKey, payload } = await analysisPayload(
      admin,
      body,
      orgId,
      playerId,
    );
    if (action === "invalidate_player_cache") {
      return json(await callAnalytics("/v1/cache/invalidate", "POST", {
        cache_key: cacheKey,
      }));
    }
    if (action !== "run_analysis" && action !== "get_cached_analysis") {
      throw new AnalyticsError("invalid_action", 400);
    }
    return json(await callAnalytics("/v1/analyze", "POST", payload));
  } catch (error) {
    const status = error instanceof AnalyticsError ? error.status : 500;
    const code = error instanceof AnalyticsError
      ? error.code
      : "analytics_gateway_failed";
    console.error(JSON.stringify({ event: "player_analytics_failed", code }));
    return json({ error: code }, status);
  }
});
