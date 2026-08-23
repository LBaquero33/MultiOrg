import {
  createClient,
  type SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  buildDevelopmentDays,
  canUseOrganizationMembership,
  canUseStaffSections,
  dateOnly,
  type DevelopmentActivity,
  type DevelopmentMedia,
  PLAYER_DEVELOPMENT_SECTIONS,
  PLAYER_DEVELOPMENT_WORKSPACE_SCHEMA_VERSION,
  normalizeWorkspaceUuid,
  type PlayerDevelopmentWorkspace,
  type ProgramAssignmentSummary,
  type ProviderSessionSummary,
  scheduledDates,
  videoPlaybackStatus,
  type WorkspaceMembership,
  type WorkspacePlayer,
} from "../_shared/player_development_workspace.ts";

const env = (name: string) => (Deno.env.get(name) ?? "").trim();
const url = env("SUPABASE_URL") || env("DHD_SUPABASE_URL");
const anonKey = env("SUPABASE_ANON_KEY") || env("DHD_SUPABASE_ANON_KEY");
const serviceKey = env("DHD_SERVICE_ROLE_KEY") ||
  env("SUPABASE_SERVICE_ROLE_KEY");

const corsHeaders = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, apikey, content-type",
  "access-control-allow-methods": "POST, OPTIONS",
};

type Row = Record<string, unknown>;
type JsonBody = {
  action?: string;
  org_id?: string;
  player_id?: string;
  team_id?: string | null;
  start_date?: string;
  end_date?: string;
  media_id?: string;
  context?: Row;
};

class WorkspaceError extends Error {
  constructor(readonly code: string, readonly status = 400) {
    super(code);
  }
}

function response(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "content-type": "application/json" },
  });
}

function stringValue(value: unknown): string | null {
  return typeof value === "string" && value.trim() ? value : null;
}

function numberValue(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) ? value : 0;
}

function boolValue(value: unknown): boolean {
  return value === true;
}

function rows(value: unknown): Row[] {
  return Array.isArray(value)
    ? value.filter((item): item is Row =>
      typeof item === "object" && item !== null
    )
    : [];
}

async function queryRows(
  query: PromiseLike<{ data: unknown; error: { message?: string } | null }>,
  code: string,
): Promise<Row[]> {
  const { data, error } = await query;
  if (error) throw new WorkspaceError(code, 500);
  return rows(data);
}

function activity(
  row: Row,
  date: string,
  kind: DevelopmentActivity["kind"],
  source: string,
  title: string,
  subtitle: string | null = null,
  warning: string | null = null,
): DevelopmentActivity {
  return {
    id: stringValue(row.id) ?? crypto.randomUUID(),
    date,
    kind,
    source,
    title,
    subtitle,
    details: row,
    warning,
  };
}

async function authenticatedActor(request: Request): Promise<string> {
  const authorization = request.headers.get("authorization") ?? "";
  if (!authorization) throw new WorkspaceError("not_authenticated", 401);
  const caller = createClient(url, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await caller.auth.getUser();
  if (error || !data.user?.id) {
    throw new WorkspaceError("not_authenticated", 401);
  }
  return normalizeWorkspaceUuid(data.user.id) ?? data.user.id.toLowerCase();
}

async function membershipFor(
  admin: SupabaseClient,
  orgId: string,
  actorId: string,
): Promise<WorkspaceMembership> {
  const { data, error } = await admin.from("sd_org_memberships")
    .select("role,status").eq("org_id", orgId).eq("user_id", actorId)
    .maybeSingle();
  if (error) throw new WorkspaceError("membership_lookup_failed", 500);
  const membership =
    data && typeof data.role === "string" && typeof data.status === "string"
      ? { role: data.role, status: data.status }
      : null;
  if (!canUseOrganizationMembership(membership)) {
    throw new WorkspaceError("organization_membership_required", 403);
  }
  return membership!;
}

type Scope = {
  membership: WorkspaceMembership;
  playerIds: Set<string>;
  teamIds: Set<string>;
  rosterRows: Row[];
};

async function resolveScope(
  admin: SupabaseClient,
  orgId: string,
  actorId: string,
  requestedTeamId: string | null,
): Promise<Scope> {
  const membership = await membershipFor(admin, orgId, actorId);
  const role = membership.role.trim().toLowerCase();
  const allRosters = await queryRows(
    admin.from("sd_player_team_memberships").select("player_id,team_id")
      .eq("organization_id", orgId).eq("active", true).is("ended_at", null),
    "player_team_scope_lookup_failed",
  );
  const allPlayerMemberships = await queryRows(
    admin.from("sd_org_memberships").select("user_id")
      .eq("org_id", orgId).eq("role", "player").eq("status", "active"),
    "player_membership_lookup_failed",
  );
  const activeOrgPlayers = new Set(
    allPlayerMemberships.map((row) => stringValue(row.user_id)).filter((
      id,
    ): id is string => !!id),
  );
  const allTeamIds = new Set(
    allRosters.map((row) => stringValue(row.team_id)).filter((
      id,
    ): id is string => !!id),
  );

  let allowedTeamIds = new Set<string>();
  let allowedPlayerIds = new Set<string>();
  if (role === "owner" || role === "admin") {
    allowedTeamIds = allTeamIds;
    allowedPlayerIds = activeOrgPlayers;
  } else if (role === "coach") {
    const assignments = await queryRows(
      admin.from("sd_coach_team_assignments")
        .select("team_id,organization_wide_access")
        .eq("organization_id", orgId).eq("coach_id", actorId)
        .eq("active", true).is("ended_at", null),
      "coach_team_scope_lookup_failed",
    );
    const organizationWide = assignments.some((row) =>
      boolValue(row.organization_wide_access)
    );
    allowedTeamIds = organizationWide ? allTeamIds : new Set(
      assignments.map((row) => stringValue(row.team_id)).filter((
        id,
      ): id is string => !!id),
    );
    allowedPlayerIds = new Set(
      allRosters.filter((row) =>
        allowedTeamIds.has(stringValue(row.team_id) ?? "")
      )
        .map((row) => stringValue(row.player_id)).filter((id): id is string =>
          !!id && activeOrgPlayers.has(id)
        ),
    );
  } else if (role === "player") {
    if (activeOrgPlayers.has(actorId)) allowedPlayerIds.add(actorId);
    for (const row of allRosters) {
      if (stringValue(row.player_id) === actorId && stringValue(row.team_id)) {
        allowedTeamIds.add(stringValue(row.team_id)!);
      }
    }
  } else if (role === "parent") {
    const links = await queryRows(
      admin.from("sd_parent_child_links").select("child_id")
        .eq("org_id", orgId).eq("parent_id", actorId),
      "parent_child_scope_lookup_failed",
    );
    allowedPlayerIds = new Set(
      links.map((row) => stringValue(row.child_id)).filter((id): id is string =>
        !!id && activeOrgPlayers.has(id)
      ),
    );
    for (const row of allRosters) {
      if (
        allowedPlayerIds.has(stringValue(row.player_id) ?? "") &&
        stringValue(row.team_id)
      ) {
        allowedTeamIds.add(stringValue(row.team_id)!);
      }
    }
  }

  if (requestedTeamId) {
    if (
      !allTeamIds.has(requestedTeamId) || !allowedTeamIds.has(requestedTeamId)
    ) {
      throw new WorkspaceError("team_not_authorized", 403);
    }
    allowedTeamIds = new Set([requestedTeamId]);
    allowedPlayerIds = new Set(
      allRosters.filter((row) => stringValue(row.team_id) === requestedTeamId)
        .map((row) => stringValue(row.player_id)).filter((id): id is string =>
          !!id && allowedPlayerIds.has(id)
        ),
    );
  }
  return {
    membership,
    playerIds: allowedPlayerIds,
    teamIds: allowedTeamIds,
    rosterRows: allRosters,
  };
}

async function workspacePlayers(
  admin: SupabaseClient,
  scope: Scope,
): Promise<WorkspacePlayer[]> {
  const ids = [...scope.playerIds];
  if (ids.length === 0) return [];
  const profiles = await queryRows(
    admin.from("profiles").select("*").in("id", ids),
    "player_profile_lookup_failed",
  );
  const teamMap = new Map<string, Set<string>>();
  for (const row of scope.rosterRows) {
    const playerId = stringValue(row.player_id);
    const teamId = stringValue(row.team_id);
    if (
      !playerId || !teamId || !scope.playerIds.has(playerId) ||
      !scope.teamIds.has(teamId)
    ) continue;
    if (!teamMap.has(playerId)) teamMap.set(playerId, new Set());
    teamMap.get(playerId)!.add(teamId);
  }
  return profiles.map((profile) => ({
    id: stringValue(profile.id)!,
    name: stringValue(profile.full_name) ?? stringValue(profile.display_name) ??
      "Player",
    avatar_path: stringValue(profile.avatar_path),
    bio: stringValue(profile.bio),
    instagram_url: stringValue(profile.instagram_url),
    perfect_game_url: stringValue(profile.perfect_game_url),
    team_ids: [...(teamMap.get(stringValue(profile.id)!) ?? [])].sort(),
  })).sort((a, b) => a.name.localeCompare(b.name));
}

function range(body: JsonBody): { start: string; end: string } {
  const today = new Date();
  const fallbackStart = new Date(today);
  fallbackStart.setUTCFullYear(fallbackStart.getUTCFullYear() - 1);
  const fallbackEnd = new Date(today);
  fallbackEnd.setUTCFullYear(fallbackEnd.getUTCFullYear() + 1);
  const start = dateOnly(body.start_date) ??
    fallbackStart.toISOString().slice(0, 10);
  const end = dateOnly(body.end_date) ?? fallbackEnd.toISOString().slice(0, 10);
  if (start > end) throw new WorkspaceError("invalid_date_range");
  return { start, end };
}

async function buildWorkspace(
  admin: SupabaseClient,
  orgId: string,
  player: WorkspacePlayer,
  membership: WorkspaceMembership,
  start: string,
  end: string,
): Promise<PlayerDevelopmentWorkspace> {
  const playerId = player.id;
  const [
    assignmentRows,
    dailyRows,
    strengthRows,
    testingRows,
    sessionRows,
    importRows,
    metricRows,
    programMediaRows,
    testingMediaRows,
  ] = await Promise.all([
    queryRows(
      admin.from("sd_program_assignments").select("*").eq("org_id", orgId).eq(
        "player_id",
        playerId,
      ),
      "program_assignments_lookup_failed",
    ),
    queryRows(
      admin.from("sd_daily_logs").select("*").eq("org_id", orgId).eq(
        "player_id",
        playerId,
      ).gte("log_date", start).lte("log_date", end),
      "daily_logs_lookup_failed",
    ),
    queryRows(
      admin.from("sd_strength_logs").select("*").eq("org_id", orgId).eq(
        "player_id",
        playerId,
      ).gte("log_date", start).lte("log_date", end),
      "strength_logs_lookup_failed",
    ),
    queryRows(
      admin.from("sd_testing_entries").select("*").eq("org_id", orgId).eq(
        "player_id",
        playerId,
      ).gte("entry_date", start).lte("entry_date", end),
      "testing_entries_lookup_failed",
    ),
    queryRows(
      admin.from("sd_bp_sessions").select("*").eq("org_id", orgId).eq(
        "player_id",
        playerId,
      ).gte("session_date", start).lte("session_date", end),
      "sessions_lookup_failed",
    ),
    queryRows(
      admin.from("sd_development_import_jobs").select("*").eq("org_id", orgId)
        .eq("player_id", playerId),
      "development_imports_lookup_failed",
    ),
    queryRows(
      admin.from("sd_player_metric_observations").select("*").eq(
        "org_id",
        orgId,
      ).eq("player_id", playerId).gte("observed_at", `${start}T00:00:00Z`).lte(
        "observed_at",
        `${end}T23:59:59Z`,
      ),
      "metric_observations_lookup_failed",
    ),
    queryRows(
      admin.from("sd_program_set_media").select("*").eq("org_id", orgId).eq(
        "player_id",
        playerId,
      ).gte("log_date", start).lte("log_date", end),
      "program_media_lookup_failed",
    ),
    queryRows(
      admin.from("sd_testing_field_media").select("*").eq("org_id", orgId).eq(
        "player_id",
        playerId,
      ),
      "testing_media_lookup_failed",
    ),
  ]);

  const templateIds = [
    ...new Set(
      assignmentRows.map((row) => stringValue(row.template_id)).filter((
        id,
      ): id is string => !!id),
    ),
  ];
  const templateRows = templateIds.length
    ? await queryRows(
      admin.from("sd_program_templates").select("*").in("id", templateIds),
      "program_templates_lookup_failed",
    )
    : [];
  const templateMap = new Map(
    templateRows.map((row) => [stringValue(row.id)!, row]),
  );
  const programDayRows = templateIds.length
    ? await queryRows(
      admin.from("sd_program_days").select("*").in("template_id", templateIds),
      "program_days_lookup_failed",
    )
    : [];
  const programDayMap = new Map<string, Row>();
  for (const row of programDayRows) {
    programDayMap.set(
      `${stringValue(row.template_id)}:${numberValue(row.week)}:${
        numberValue(row.day_index)
      }`,
      row,
    );
  }

  const metricDefinitionIds = [
    ...new Set(
      metricRows.map((row) => stringValue(row.metric_definition_id)).filter((
        id,
      ): id is string => !!id),
    ),
  ];
  const metricDefinitionRows = metricDefinitionIds.length
    ? await queryRows(
      admin.from("sd_development_metric_definitions")
        .select("id,canonical_key,display_name,canonical_unit")
        .in("id", metricDefinitionIds),
      "metric_definitions_lookup_failed",
    )
    : [];
  const metricDefinitions = new Map(
    metricDefinitionRows.map((row) => [stringValue(row.id)!, row]),
  );

  const assignments: ProgramAssignmentSummary[] = [];
  const scheduled = new Set<string>();
  for (const row of assignmentRows) {
    const id = stringValue(row.id);
    const templateId = stringValue(row.template_id);
    const startDate = dateOnly(row.start_date);
    if (!id || !templateId || !startDate) continue;
    const template = templateMap.get(templateId) ?? {};
    const weekdays = Array.isArray(template.lift_weekdays)
      ? template.lift_weekdays.filter((value): value is number =>
        typeof value === "number"
      )
      : [];
    const dates = scheduledDates({
      start_date: startDate,
      end_date: dateOnly(row.ended_at),
      weeks: Math.max(1, numberValue(template.weeks)),
      lift_weekdays: weekdays,
    });
    for (const date of dates) {
      if (date >= start && date <= end) scheduled.add(date);
    }
    const endDate = dateOnly(row.ended_at) ?? dates.at(-1) ?? startDate;
    assignments.push({
      id,
      template_id: templateId,
      template_name: stringValue(template.name) ?? "Program",
      program_kind: stringValue(template.program_kind) ?? "strength",
      start_date: startDate,
      end_date: endDate,
      status: row.ended_at ? "ended" : "active",
      notes: stringValue(row.notes),
    });
  }

  const activities: DevelopmentActivity[] = [];
  for (const row of dailyRows) {
    const date = dateOnly(row.log_date);
    if (date) {
      activities.push(activity(row, date, "daily_log", "manual", "Daily log"));
    }
  }
  for (const row of strengthRows) {
    const date = dateOnly(row.log_date);
    if (!date) continue;
    const plan = programDayMap.get(
      `${stringValue(row.template_id)}:${numberValue(row.week)}:${
        numberValue(row.day_index)
      }`,
    );
    activities.push(
      activity(
        { ...row, planned_exercises: plan?.exercises ?? [] },
        date,
        "program",
        "program",
        stringValue(row.exercise_name) ?? "Program exercise",
      ),
    );
  }
  for (const row of testingRows) {
    const date = dateOnly(row.entry_date);
    if (date) {
      activities.push(
        activity(row, date, "testing", "manual", "Testing session"),
      );
    }
  }
  for (const row of sessionRows) {
    const date = dateOnly(row.session_date);
    if (!date) continue;
    const source = stringValue(row.source) ?? "manual";
    const kind = stringValue(row.activity_type) ?? "hitting";
    activities.push(
      activity(
        row,
        date,
        "session",
        source,
        kind === "bullpen" ? "Bullpen session" : "Hitting session",
      ),
    );
  }
  for (const row of importRows) {
    const date = dateOnly(row.completed_at) ?? dateOnly(row.created_at);
    if (!date || date < start || date > end) continue;
    const provider = stringValue(row.provider) ??
      stringValue(row.import_source) ?? "import";
    const warning = numberValue(row.rejected_rows) > 0
      ? "Some imported rows could not be parsed."
      : null;
    activities.push(
      activity(
        row,
        date,
        "provider_import",
        provider,
        `${provider} import`,
        stringValue(row.file_name),
        warning,
      ),
    );
  }
  for (const row of metricRows) {
    const date = dateOnly(row.observed_at);
    if (!date) continue;
    const definition = metricDefinitions.get(
      stringValue(row.metric_definition_id) ?? "",
    );
    activities.push(
      activity(
        {
          ...row,
          metric_key: stringValue(definition?.canonical_key),
          metric_name: stringValue(definition?.display_name),
          canonical_unit: stringValue(definition?.canonical_unit),
        },
        date,
        "provider_metric",
        stringValue(row.source_system) ?? "provider",
        stringValue(definition?.display_name) ?? "Provider metric",
      ),
    );
  }

  const media: DevelopmentMedia[] = [];
  for (const row of programMediaRows) {
    const id = stringValue(row.id);
    const date = dateOnly(row.log_date);
    if (!id || !date) continue;
    media.push({
      id,
      date,
      kind: "program_set_video",
      title: `${stringValue(row.exercise_name) ?? "Exercise"} set ${
        numberValue(row.set_number)
      }`,
      file_name: stringValue(row.file_name),
      mime_type: stringValue(row.mime_type),
      source: "program",
      playback_status: stringValue(row.mime_type) === "video/mp4"
        ? "ready"
        : "needs_conversion",
    });
  }
  const testingById = new Map(
    testingRows.map((row) => [stringValue(row.id)!, dateOnly(row.entry_date)]),
  );
  for (const row of testingMediaRows) {
    const id = stringValue(row.id);
    const date = testingById.get(stringValue(row.testing_entry_id) ?? "");
    if (!id || !date) continue;
    media.push({
      id,
      date,
      kind: "testing_field_video",
      title: `${stringValue(row.field_key) ?? "Testing field"} video`,
      file_name: stringValue(row.file_name),
      mime_type: stringValue(row.mime_type),
      source: "testing",
      playback_status: stringValue(row.mime_type) === "video/mp4"
        ? "ready"
        : "needs_conversion",
    });
  }
  for (const row of sessionRows) {
    const id = stringValue(row.id);
    const date = dateOnly(row.session_date);
    if (!id || !date || !stringValue(row.video_path)) continue;
    media.push({
      id,
      date,
      kind: "session_video",
      title: stringValue(row.activity_type) === "bullpen"
        ? "Bullpen video"
        : "Hitting video",
      file_name: stringValue(row.video_file_name),
      mime_type: stringValue(row.video_mime_type),
      source: stringValue(row.source) ?? "video",
      playback_status: videoPlaybackStatus(
        stringValue(row.video_mime_type),
        stringValue(row.video_path),
      ),
    });
  }
  for (const row of importRows) {
    const id = stringValue(row.id);
    const date = dateOnly(row.completed_at) ?? dateOnly(row.created_at);
    if (
      !id || !date || !stringValue(row.storage_bucket) ||
      !stringValue(row.storage_path)
    ) continue;
    media.push({
      id,
      date,
      kind: "import_file",
      title: stringValue(row.provider)
        ? `${stringValue(row.provider)} source file`
        : "Imported source file",
      file_name: stringValue(row.file_name),
      mime_type: stringValue(row.original_file_type),
      source: stringValue(row.provider) ?? "import",
      playback_status: "ready",
    });
  }

  const providers = new Map<string, ProviderSessionSummary>();
  for (
    const item of activities.filter((item) =>
      item.kind === "session" || item.kind === "provider_import"
    )
  ) {
    const key = `${item.source}:${item.date}:${item.id}`;
    providers.set(key, {
      id: item.id,
      date: item.date,
      provider: item.source,
      activity_type: stringValue(item.details.activity_type) ??
        (item.kind === "session" ? "hitting" : "import"),
      status: stringValue(item.details.status) ?? "completed",
      metric_count: metricRows.filter((metric) =>
        dateOnly(metric.observed_at) === item.date &&
        (stringValue(metric.source_system) ?? "provider") === item.source
      ).length,
      has_file: media.some((entry) =>
        entry.date === item.date && entry.kind === "import_file" &&
        entry.source === item.source
      ),
      has_video: media.some((entry) =>
        entry.date === item.date && entry.kind === "session_video"
      ),
    });
  }

  const sections = canUseStaffSections(membership)
    ? PLAYER_DEVELOPMENT_SECTIONS
    : PLAYER_DEVELOPMENT_SECTIONS.slice(0, 6);
  return {
    schema_version: PLAYER_DEVELOPMENT_WORKSPACE_SCHEMA_VERSION,
    organization_id: orgId,
    generated_at: new Date().toISOString(),
    sections,
    player,
    assignments: assignments.sort((a, b) =>
      b.start_date.localeCompare(a.start_date)
    ),
    days: buildDevelopmentDays(scheduled, activities, media),
    provider_sessions: [...providers.values()].sort((a, b) =>
      b.date.localeCompare(a.date)
    ),
  };
}

async function playback(
  admin: SupabaseClient,
  scope: Scope,
  mediaId: string,
): Promise<{ url: string; expires_in: number; playback_status: string }> {
  const candidates = [
    {
      table: "sd_program_set_media",
      bucket: "program-set-videos",
      path: "storage_path",
      player: "player_id",
      mime: "mime_type",
    },
    {
      table: "sd_testing_field_media",
      bucket: "player-session-videos",
      path: "storage_path",
      player: "player_id",
      mime: "mime_type",
    },
    {
      table: "sd_bp_sessions",
      bucket: "player-session-videos",
      path: "video_path",
      player: "player_id",
      mime: "video_mime_type",
    },
    {
      table: "sd_development_import_jobs",
      bucket: null,
      path: "storage_path",
      player: "player_id",
      mime: "original_file_type",
    },
  ] as const;
  for (const candidate of candidates) {
    const { data, error } = await admin.from(candidate.table).select("*").eq(
      "id",
      mediaId,
    ).maybeSingle();
    if (error) throw new WorkspaceError("media_lookup_failed", 500);
    if (!data) continue;
    const row = data as Row;
    if (!scope.playerIds.has(stringValue(row[candidate.player]) ?? "")) {
      throw new WorkspaceError("media_not_authorized", 403);
    }
    const path = stringValue(row[candidate.path]);
    const bucket = candidate.bucket ?? stringValue(row.storage_bucket);
    if (!path || !bucket) throw new WorkspaceError("media_not_available", 404);
    const mime = stringValue(row[candidate.mime]);
    if (
      candidate.bucket && videoPlaybackStatus(mime, path) === "needs_conversion"
    ) {
      return { url: "", expires_in: 0, playback_status: "needs_conversion" };
    }
    const { data: signed, error: signError } = await admin.storage.from(bucket)
      .createSignedUrl(path, 900);
    if (signError || !signed?.signedUrl) {
      throw new WorkspaceError("media_signing_failed", 500);
    }
    return { url: signed.signedUrl, expires_in: 900, playback_status: "ready" };
  }
  throw new WorkspaceError("media_not_found", 404);
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return response({ error: "method_not_allowed" }, 405);
  }
  if (!url || !anonKey || !serviceKey) {
    return response({ error: "missing_configuration" }, 500);
  }

  try {
    const actorId = await authenticatedActor(request);
    const body = await request.json() as JsonBody;
    const orgId = normalizeWorkspaceUuid(body.org_id);
    if (!orgId) throw new WorkspaceError("organization_required");
    const admin = createClient(url, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const scope = await resolveScope(
      admin,
      orgId,
      actorId,
      normalizeWorkspaceUuid(body.team_id),
    );

    if (body.action === "list_players") {
      return response({
        schema_version: PLAYER_DEVELOPMENT_WORKSPACE_SCHEMA_VERSION,
        organization_id: orgId,
        players: await workspacePlayers(admin, scope),
      });
    }

    if (body.action === "get_workspace" || body.action === "get_day_detail") {
      const playerId = normalizeWorkspaceUuid(body.player_id);
      if (!playerId || !scope.playerIds.has(playerId)) {
        throw new WorkspaceError("player_not_authorized", 403);
      }
      const players = await workspacePlayers(admin, scope);
      const player = players.find((item) => item.id === playerId);
      if (!player) throw new WorkspaceError("player_not_found", 404);
      const dates =
        body.action === "get_day_detail" && dateOnly(body.start_date)
          ? {
            start: dateOnly(body.start_date)!,
            end: dateOnly(body.start_date)!,
          }
          : range(body);
      const workspace = await buildWorkspace(
        admin,
        orgId,
        player,
        scope.membership,
        dates.start,
        dates.end,
      );
      if (body.action === "get_day_detail") {
        return response({
          schema_version: workspace.schema_version,
          organization_id: orgId,
          player: workspace.player,
          day: workspace.days.find((day) => day.date === dates.start) ?? null,
        });
      }
      return response(workspace);
    }

    if (body.action === "get_video_playback") {
      const mediaId = normalizeWorkspaceUuid(body.media_id);
      if (!mediaId) throw new WorkspaceError("media_id_required");
      return response(await playback(admin, scope, mediaId));
    }

    if (body.action === "create_video_upload") {
      const context = body.context ?? {};
      const playerId = normalizeWorkspaceUuid(context.player_id);
      const kind = stringValue(context.kind);
      if (!playerId || !scope.playerIds.has(playerId)) {
        throw new WorkspaceError("player_not_authorized", 403);
      }
      if (
        !kind ||
        !["program_set_video", "testing_field_video", "session_video"].includes(
          kind,
        )
      ) throw new WorkspaceError("video_context_invalid");
      const role = scope.membership.role.toLowerCase();
      if (role === "parent") {
        throw new WorkspaceError("video_upload_not_authorized", 403);
      }
      if (role === "player" && playerId !== actorId) {
        throw new WorkspaceError("video_upload_not_authorized", 403);
      }
      const bucket = kind === "program_set_video"
        ? "program-set-videos"
        : "player-session-videos";
      const path = `${orgId}/${playerId}/${crypto.randomUUID()}.mp4`;
      const { data, error } = await admin.storage.from(bucket)
        .createSignedUploadUrl(path);
      if (error || !data) {
        throw new WorkspaceError("video_upload_signing_failed", 500);
      }
      return response({
        bucket,
        path,
        token: data.token,
        signed_url: data.signedUrl,
        max_bytes: 262144000,
        required_mime_type: "video/mp4",
      });
    }

    throw new WorkspaceError("unknown_action", 404);
  } catch (error) {
    const failure = error instanceof WorkspaceError
      ? error
      : new WorkspaceError("workspace_unavailable", 500);
    console.error(
      JSON.stringify({
        event: "player_development_workspace_failed",
        code: failure.code,
        status: failure.status,
      }),
    );
    return response({ error: failure.code }, failure.status);
  }
});
