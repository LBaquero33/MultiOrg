import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  type CalendarSource,
  type CalendarSourceKind,
  canApplyGoogleEdit,
  externalEventPatch,
  googleAuthorizationURL,
  type GoogleCalendarEvent,
  openSecret,
  pkceChallenge,
  randomOpaqueValue,
  safeCalendarError,
  sealSecret,
  sha256Hex,
  sourceToGoogleEvent,
} from "../_shared/calendar_integrations.ts";

const cors = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers":
    "authorization, apikey, content-type, x-home-plate-calendar-worker-secret, x-goog-channel-id, x-goog-channel-token, x-goog-resource-state",
  "access-control-allow-methods": "GET, POST, OPTIONS",
};

const json = (status: number, body: Record<string, unknown>) =>
  new Response(
    JSON.stringify(body),
    { status, headers: { ...cors, "content-type": "application/json" } },
  );

const text = (value: unknown) => typeof value === "string" ? value.trim() : "";
const uuid = (value: unknown) => {
  const candidate = text(value).toLowerCase();
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
      .test(candidate)
    ? candidate
    : null;
};
const env = (name: string) => text(Deno.env.get(name));

// The function intentionally keeps the generated database schema out of the
// Edge bundle; runtime rows are narrowed at each authorization boundary.
// deno-lint-ignore no-explicit-any
type Admin = any;
type Connection = {
  id: string;
  user_id: string;
  organization_id: string;
  calendar_id: string;
  access_token_ciphertext: string;
  refresh_token_ciphertext: string | null;
  token_expires_at: string | null;
  sync_token_ciphertext: string | null;
  channel_id: string | null;
  channel_token_hash: string | null;
  status: string;
};

function requiredEnvironment() {
  const values = {
    url: env("SUPABASE_URL"),
    anon: env("SUPABASE_ANON_KEY") || env("SUPABASE_PUBLISHABLE_KEY"),
    service: env("SUPABASE_SERVICE_ROLE_KEY"),
    clientId: env("GOOGLE_CALENDAR_CLIENT_ID"),
    clientSecret: env("GOOGLE_CALENDAR_CLIENT_SECRET"),
    redirectUri: env("GOOGLE_CALENDAR_REDIRECT_URI"),
    encryptionKey: env("CALENDAR_TOKEN_ENCRYPTION_KEY_BASE64"),
    webhookBase: env("CALENDAR_WEBHOOK_BASE_URL"),
    workerSecret: env("CALENDAR_SYNC_WORKER_SECRET"),
  };
  if (!values.url || !values.anon || !values.service) {
    throw new Error("missing_supabase_secrets");
  }
  if (
    !values.clientId || !values.clientSecret || !values.redirectUri ||
    !values.encryptionKey
  ) {
    throw new Error("calendar_integration_not_configured");
  }
  return values;
}

async function authenticatedContext(req: Request, organizationId: string) {
  const values = requiredEnvironment();
  const token = (req.headers.get("authorization") ?? "").replace(
    /^Bearer\s+/i,
    "",
  ).trim();
  if (!token) throw new Error("missing_auth");
  const actorClient = createClient(values.url, values.anon, {
    global: { headers: { Authorization: `Bearer ${token}` } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await actorClient.auth.getUser(token);
  if (error || !data.user?.id) throw new Error("invalid_auth");
  const admin = createClient(values.url, values.service, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: membership, error: membershipError } = await admin.from(
    "sd_org_memberships",
  )
    .select("role,status").eq("org_id", organizationId).eq(
      "user_id",
      data.user.id,
    )
    .eq("status", "active").maybeSingle();
  if (membershipError) throw new Error("membership_lookup_failed");
  if (!membership) throw new Error("organization_membership_required");
  return {
    values,
    admin,
    actorId: data.user.id,
    role: text(membership.role).toLowerCase(),
  };
}

function allowedReturnURL(value: string): string | null {
  try {
    const url = new URL(value);
    const allowed = env("CALENDAR_ALLOWED_RETURN_ORIGINS").split(",").map((
      item,
    ) => item.trim()).filter(Boolean);
    if (
      url.protocol !== "https:" && url.hostname !== "localhost" &&
      url.hostname !== "127.0.0.1"
    ) return null;
    if (allowed.length && !allowed.includes(url.origin)) return null;
    return url.toString();
  } catch {
    return null;
  }
}

async function refreshAccessToken(
  admin: Admin,
  connection: Connection,
  values: ReturnType<typeof requiredEnvironment>,
) {
  const expiresAt = connection.token_expires_at
    ? new Date(connection.token_expires_at).valueOf()
    : 0;
  if (expiresAt > Date.now() + 60_000) {
    return await openSecret(
      connection.access_token_ciphertext,
      values.encryptionKey,
    );
  }
  if (!connection.refresh_token_ciphertext) {
    throw new Error("google_reauthorization_required");
  }
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: values.clientId,
      client_secret: values.clientSecret,
      refresh_token: await openSecret(
        connection.refresh_token_ciphertext,
        values.encryptionKey,
      ),
      grant_type: "refresh_token",
    }),
  });
  const payload = await response.json() as Record<string, unknown>;
  if (!response.ok || !text(payload.access_token)) {
    throw new Error(text(payload.error) || "google_token_refresh_failed");
  }
  const accessToken = text(payload.access_token);
  await admin.from("sd_calendar_connections").update({
    access_token_ciphertext: await sealSecret(
      accessToken,
      values.encryptionKey,
    ),
    token_expires_at: new Date(
      Date.now() + Number(payload.expires_in ?? 3600) * 1000,
    ).toISOString(),
    status: "active",
    last_error_code: null,
    updated_at: new Date().toISOString(),
  }).eq("id", connection.id);
  return accessToken;
}

async function googleRequest(
  token: string,
  path: string,
  init: RequestInit = {},
) {
  const response = await fetch(
    `https://www.googleapis.com/calendar/v3${path}`,
    {
      ...init,
      headers: {
        authorization: `Bearer ${token}`,
        "content-type": "application/json",
        ...init.headers,
      },
    },
  );
  if (response.status === 204 || response.status === 404) {
    return { status: response.status, payload: null };
  }
  const payload = await response.json() as Record<string, unknown>;
  if (!response.ok) {
    throw new Error(
      `google_calendar_${response.status}_${
        text(payload.error) || "request_failed"
      }`,
    );
  }
  return { status: response.status, payload };
}

async function loadSource(
  admin: Admin,
  kind: CalendarSourceKind,
  sourceId: string,
): Promise<(CalendarSource & { eventType?: string }) | null> {
  if (kind === "sd_events") {
    const { data, error } = await admin.from("sd_events").select(
      "id,org_id,team_id,title,description,event_type,scheduled_start,scheduled_end,location_name,venue_address,status,updated_at,created_by",
    )
      .eq("id", sourceId).maybeSingle();
    if (error) throw new Error("calendar_source_load_failed");
    return data
      ? {
        kind,
        id: data.id,
        organizationId: data.org_id,
        teamId: data.team_id,
        title: data.title,
        description: data.description,
        eventType: data.event_type,
        startAt: data.scheduled_start,
        endAt: data.scheduled_end,
        location: [data.location_name, data.venue_address].filter(Boolean).join(
          " — ",
        ) || null,
        status: data.status,
        updatedAt: data.updated_at,
        createdBy: data.created_by,
      }
      : null;
  }
  if (kind === "sd_team_events") {
    const { data, error } = await admin.from("sd_team_events").select(
      "id,organization_id,team_id,title,description,event_type,start_at,end_at,location_name,address,status,updated_at,created_by",
    )
      .eq("id", sourceId).maybeSingle();
    if (error) throw new Error("calendar_source_load_failed");
    return data
      ? {
        kind,
        id: data.id,
        organizationId: data.organization_id,
        teamId: data.team_id,
        title: data.title,
        description: data.description,
        eventType: data.event_type,
        startAt: data.start_at,
        endAt: data.end_at,
        location:
          [data.location_name, data.address].filter(Boolean).join(" — ") ||
          null,
        status: data.status,
        updatedAt: data.updated_at,
        createdBy: data.created_by,
      }
      : null;
  }
  const { data, error } = await admin.from("sd_facility_bookings")
    .select(
      "id,org_id,player_id,created_by,title,activity_type,start_at,end_at,status,notes,updated_at,sd_facilities(name)",
    )
    .eq("id", sourceId).maybeSingle();
  if (error) throw new Error("calendar_source_load_failed");
  const facility = data?.sd_facilities as unknown as { name?: string } | null;
  return data
    ? {
      kind,
      id: data.id,
      organizationId: data.org_id,
      teamId: null,
      title: data.title ||
        `${text(data.activity_type).replaceAll("_", " ")} booking`,
      description: data.notes,
      startAt: data.start_at,
      endAt: data.end_at,
      location: facility?.name ?? null,
      status: data.status,
      updatedAt: data.updated_at,
      createdBy: data.created_by,
      playerId: data.player_id,
    }
    : null;
}

async function sourceAuthority(
  admin: Admin,
  connection: Connection,
  source: CalendarSource & { eventType?: string },
) {
  const { data: membership } = await admin.from("sd_org_memberships").select(
    "role,status",
  )
    .eq("org_id", source.organizationId).eq("user_id", connection.user_id).eq(
      "status",
      "active",
    ).maybeSingle();
  if (!membership) {
    return {
      visible: false,
      editable: false,
      role: "",
      capabilities: [] as string[],
    };
  }
  const role = text(membership.role).toLowerCase();
  let capabilities: string[] = [];
  if (source.teamId && role === "coach") {
    const result = await admin.rpc("sd_resolve_team_capabilities", {
      target_organization: source.organizationId,
      target_team: source.teamId,
      target_actor: connection.user_id,
    });
    if (result.error) throw new Error("capability_resolution_failed");
    capabilities = (result.data ?? []).map(String);
  }
  let visible = role === "owner" || role === "admin";
  if (role === "coach") {
    visible = source.teamId
      ? capabilities.includes("view_team_schedule")
      : source.createdBy === connection.user_id;
  }
  if (role === "player") {
    if (
      source.playerId === connection.user_id ||
      source.createdBy === connection.user_id
    ) visible = true;
    else if (source.teamId) {
      const result = await admin.from("sd_player_team_memberships").select("id")
        .eq("organization_id", source.organizationId).eq(
          "team_id",
          source.teamId,
        )
        .eq("player_id", connection.user_id).eq("active", true).is(
          "ended_at",
          null,
        ).maybeSingle();
      visible = Boolean(result.data);
    }
  }
  if (role === "parent" && source.teamId) {
    const links = await admin.from("sd_parent_child_links").select("child_id")
      .eq("org_id", source.organizationId).eq("parent_id", connection.user_id);
    const childIds = (links.data ?? []).map((row: { child_id: string }) =>
      row.child_id
    );
    if (childIds.length) {
      const result = await admin.from("sd_player_team_memberships").select("id")
        .eq("organization_id", source.organizationId).eq(
          "team_id",
          source.teamId,
        )
        .in("player_id", childIds).eq("active", true).is("ended_at", null)
        .limit(1);
      visible = Boolean(result.data?.length);
    }
  }
  return {
    visible,
    editable: visible && canApplyGoogleEdit({
      role,
      capabilities,
      sourceKind: source.kind,
      eventType: source.eventType,
    }),
    role,
    capabilities,
  };
}

async function cancelProviderEvent(
  admin: Admin,
  connection: Connection,
  token: string,
  kind: CalendarSourceKind,
  sourceId: string,
) {
  const link = await admin.from("sd_calendar_event_links").select(
    "id,provider_event_id",
  )
    .eq("connection_id", connection.id).eq("source_kind", kind).eq(
      "source_id",
      sourceId,
    ).maybeSingle();
  if (!link.data) return;
  await googleRequest(
    token,
    `/calendars/${encodeURIComponent(connection.calendar_id)}/events/${
      encodeURIComponent(link.data.provider_event_id)
    }`,
    { method: "DELETE" },
  );
  await admin.from("sd_calendar_event_links").delete().eq("id", link.data.id);
}

async function pushSource(
  admin: Admin,
  connection: Connection,
  values: ReturnType<typeof requiredEnvironment>,
  kind: CalendarSourceKind,
  sourceId: string,
) {
  const token = await refreshAccessToken(admin, connection, values);
  const source = await loadSource(admin, kind, sourceId);
  if (!source) {
    await cancelProviderEvent(admin, connection, token, kind, sourceId);
    return "source_missing";
  }
  const authority = await sourceAuthority(admin, connection, source);
  if (!authority.visible) {
    await cancelProviderEvent(admin, connection, token, kind, sourceId);
    return "not_visible";
  }
  const cancelled =
    ["canceled", "cancelled", "denied"].includes(source.status) ||
    (kind === "sd_facility_bookings" && source.status !== "approved");
  if (cancelled) {
    await cancelProviderEvent(admin, connection, token, kind, sourceId);
    return "cancelled";
  }
  const link = await admin.from("sd_calendar_event_links").select(
    "id,provider_event_id",
  )
    .eq("connection_id", connection.id).eq("source_kind", kind).eq(
      "source_id",
      sourceId,
    ).maybeSingle();
  const mapped = sourceToGoogleEvent(source);
  const path = link.data
    ? `/calendars/${encodeURIComponent(connection.calendar_id)}/events/${
      encodeURIComponent(link.data.provider_event_id)
    }?sendUpdates=none`
    : `/calendars/${
      encodeURIComponent(connection.calendar_id)
    }/events?sendUpdates=none`;
  const result = await googleRequest(token, path, {
    method: link.data ? "PATCH" : "POST",
    body: JSON.stringify(mapped),
  });
  const event = result.payload as GoogleCalendarEvent;
  if (!event.id) throw new Error("google_event_id_missing");
  await admin.from("sd_calendar_event_links").upsert({
    connection_id: connection.id,
    organization_id: source.organizationId,
    source_kind: kind,
    source_id: sourceId,
    provider_event_id: event.id,
    provider_etag: event.etag ?? null,
    last_source: "home_plate",
    last_provider_updated_at: event.updated ?? null,
    last_home_plate_updated_at: source.updatedAt,
    updated_at: new Date().toISOString(),
  }, { onConflict: "connection_id,source_kind,source_id" });
  return link.data ? "updated" : "created";
}

async function applyGoogleChange(
  admin: Admin,
  connection: Connection,
  link: Record<string, unknown>,
  event: GoogleCalendarEvent,
) {
  const kind = text(link.source_kind) as CalendarSourceKind;
  const source = await loadSource(admin, kind, text(link.source_id));
  if (!source) return "source_missing";
  const authority = await sourceAuthority(admin, connection, source);
  if (!authority.editable) return "read_only";
  if (event.status === "cancelled") {
    const table = kind;
    const status = kind === "sd_team_events" ? "cancelled" : "canceled";
    const statusColumn = kind === "sd_facility_bookings" ? "status" : "status";
    const result = await admin.from(table).update({ [statusColumn]: status })
      .eq("id", source.id);
    if (result.error) throw new Error("calendar_source_update_failed");
    return "cancelled";
  }
  const patch = externalEventPatch(event);
  if (!patch) return "invalid_provider_event";
  const updates = kind === "sd_team_events"
    ? {
      title: patch.title,
      description: patch.description,
      start_at: patch.startAt,
      end_at: patch.endAt,
      location_name: patch.location,
      updated_by: connection.user_id,
    }
    : {
      title: patch.title,
      description: patch.description,
      scheduled_start: patch.startAt,
      scheduled_end: patch.endAt,
      location_name: patch.location,
      updated_by: connection.user_id,
    };
  let updateQuery = admin.from(kind).update(updates).eq("id", source.id);
  updateQuery = kind === "sd_events"
    ? updateQuery.eq("org_id", source.organizationId)
    : updateQuery.eq("organization_id", source.organizationId);
  const result = await updateQuery;
  if (result.error) throw new Error("calendar_source_update_failed");
  await admin.from("sd_calendar_event_links").update({
    provider_etag: event.etag ?? null,
    last_source: "google",
    last_provider_updated_at: event.updated ?? null,
    updated_at: new Date().toISOString(),
  }).eq("id", text(link.id));
  return "updated";
}

async function pullLinkedEvents(
  admin: Admin,
  connection: Connection,
  values: ReturnType<typeof requiredEnvironment>,
) {
  const token = await refreshAccessToken(admin, connection, values);
  const links = await admin.from("sd_calendar_event_links").select(
    "id,source_kind,source_id,provider_event_id,provider_etag",
  )
    .eq("connection_id", connection.id).limit(500);
  if (links.error) throw new Error("calendar_link_load_failed");
  let changed = 0;
  for (const link of links.data ?? []) {
    const result = await googleRequest(
      token,
      `/calendars/${encodeURIComponent(connection.calendar_id)}/events/${
        encodeURIComponent(link.provider_event_id)
      }`,
    );
    if (result.status === 404) continue;
    const event = result.payload as GoogleCalendarEvent;
    if (event.etag && event.etag === link.provider_etag) continue;
    const outcome = await applyGoogleChange(admin, connection, link, event);
    if (["updated", "cancelled"].includes(outcome)) changed += 1;
  }
  await admin.from("sd_calendar_connections").update({
    last_synced_at: new Date().toISOString(),
    last_error_code: null,
  }).eq("id", connection.id);
  return changed;
}

async function startWatch(
  admin: Admin,
  connection: Connection,
  values: ReturnType<typeof requiredEnvironment>,
) {
  if (!values.webhookBase) return;
  const token = await refreshAccessToken(admin, connection, values);
  const channelId = crypto.randomUUID();
  const channelToken = randomOpaqueValue(32);
  const address = `${
    values.webhookBase.replace(/\/$/, "")
  }/functions/v1/calendar-integrations?mode=google_webhook`;
  const result = await googleRequest(
    token,
    `/calendars/${encodeURIComponent(connection.calendar_id)}/events/watch`,
    {
      method: "POST",
      body: JSON.stringify({
        id: channelId,
        type: "web_hook",
        address,
        token: channelToken,
        params: { ttl: "604800" },
      }),
    },
  );
  await admin.from("sd_calendar_connections").update({
    channel_id: channelId,
    channel_resource_id: text(result.payload?.resourceId) || null,
    channel_token_hash: await sha256Hex(channelToken),
    channel_expires_at: text(result.payload?.expiration)
      ? new Date(Number(result.payload?.expiration)).toISOString()
      : new Date(Date.now() + 7 * 86_400_000).toISOString(),
  }).eq("id", connection.id);
}

async function queueInitialHomePlateSources(
  admin: Admin,
  connection: Connection,
) {
  const definitions: Array<
    { table: CalendarSourceKind; organizationColumn: string }
  > = [
    { table: "sd_events", organizationColumn: "org_id" },
    { table: "sd_team_events", organizationColumn: "organization_id" },
    { table: "sd_facility_bookings", organizationColumn: "org_id" },
  ];
  const jobs: Array<Record<string, unknown>> = [];
  for (const definition of definitions) {
    let offset = 0;
    while (true) {
      const result = await admin.from(definition.table).select("id")
        .eq(definition.organizationColumn, connection.organization_id)
        .range(offset, offset + 499);
      if (result.error) throw new Error("calendar_initial_source_load_failed");
      const rows = result.data ?? [];
      jobs.push(...rows.map((row: { id: string }) => ({
        connection_id: connection.id,
        organization_id: connection.organization_id,
        source_kind: definition.table,
        source_id: row.id,
        operation: "upsert",
      })));
      if (rows.length < 500) break;
      offset += rows.length;
    }
  }
  for (let offset = 0; offset < jobs.length; offset += 500) {
    const inserted = await admin.from("sd_calendar_sync_jobs").insert(
      jobs.slice(offset, offset + 500),
    );
    if (inserted.error) throw new Error("calendar_initial_queue_failed");
  }
  return jobs.length;
}

async function processWorker(
  admin: Admin,
  values: ReturnType<typeof requiredEnvironment>,
) {
  const claim = await admin.rpc("sd_claim_calendar_sync_jobs", { p_limit: 20 });
  if (claim.error) throw new Error("calendar_job_claim_failed");
  let completed = 0;
  for (const job of claim.data ?? []) {
    try {
      const connectionResult = await admin.from("sd_calendar_connections")
        .select("*").eq("id", job.connection_id).eq("status", "active")
        .maybeSingle();
      if (!connectionResult.data) {
        throw new Error("calendar_connection_inactive");
      }
      const connection = connectionResult.data as Connection;
      if (job.operation === "pull") {
        await pullLinkedEvents(admin, connection, values);
      } else if (job.operation === "renew_watch") {
        await startWatch(admin, connection, values);
      } else if (job.source_id) {
        await pushSource(
          admin,
          connection,
          values,
          job.source_kind as CalendarSourceKind,
          job.source_id,
        );
      }
      await admin.from("sd_calendar_sync_jobs").update({
        status: "completed",
        completed_at: new Date().toISOString(),
        last_error_code: null,
      }).eq("id", job.id);
      completed += 1;
    } catch (error) {
      const code = safeCalendarError(error);
      const retryable = job.attempt_count < 5 &&
        code !== "google_reauthorization_required";
      await admin.from("sd_calendar_sync_jobs").update({
        status: retryable ? "retryable" : "failed",
        next_attempt_at: new Date(
          Date.now() + Math.min(3600, 2 ** job.attempt_count * 30) * 1000,
        ).toISOString(),
        last_error_code: code,
      }).eq("id", job.id);
      await admin.from("sd_calendar_connections").update({
        status: code === "google_reauthorization_required"
          ? "needs_reauthorization"
          : "active",
        last_error_code: code,
      }).eq("id", job.connection_id);
      console.error(
        JSON.stringify({
          event: "calendar_sync_job_failed",
          code,
          operation: job.operation,
          source_kind: job.source_kind,
        }),
      );
    }
  }
  return { claimed: (claim.data ?? []).length, completed };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: cors });
  }
  try {
    const values = requiredEnvironment();
    const admin = createClient(values.url, values.service, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const url = new URL(req.url);

    if (
      req.method === "GET" && url.searchParams.get("code") &&
      url.searchParams.get("state")
    ) {
      const state = text(url.searchParams.get("state"));
      const stateHash = await sha256Hex(state);
      const stateResult = await admin.from("sd_calendar_oauth_states").select(
        "*",
      )
        .eq("state_hash", stateHash).is("consumed_at", null).gt(
          "expires_at",
          new Date().toISOString(),
        ).maybeSingle();
      if (!stateResult.data) {
        return new Response("Invalid or expired calendar connection.", {
          status: 400,
        });
      }
      const tokenResponse = await fetch("https://oauth2.googleapis.com/token", {
        method: "POST",
        headers: { "content-type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({
          client_id: values.clientId,
          client_secret: values.clientSecret,
          code: text(url.searchParams.get("code")),
          code_verifier: await openSecret(
            stateResult.data.code_verifier_ciphertext,
            values.encryptionKey,
          ),
          redirect_uri: values.redirectUri,
          grant_type: "authorization_code",
        }),
      });
      const tokens = await tokenResponse.json() as Record<string, unknown>;
      if (!tokenResponse.ok || !text(tokens.access_token)) {
        throw new Error(text(tokens.error) || "google_code_exchange_failed");
      }
      const existing = await admin.from("sd_calendar_connections").select(
        "refresh_token_ciphertext",
      )
        .eq("user_id", stateResult.data.user_id).eq(
          "organization_id",
          stateResult.data.organization_id,
        )
        .eq("provider", "google").eq("calendar_id", "primary").maybeSingle();
      const refreshCiphertext = text(tokens.refresh_token)
        ? await sealSecret(text(tokens.refresh_token), values.encryptionKey)
        : existing.data?.refresh_token_ciphertext ?? null;
      const saved = await admin.from("sd_calendar_connections").upsert({
        user_id: stateResult.data.user_id,
        organization_id: stateResult.data.organization_id,
        provider: "google",
        calendar_id: "primary",
        access_token_ciphertext: await sealSecret(
          text(tokens.access_token),
          values.encryptionKey,
        ),
        refresh_token_ciphertext: refreshCiphertext,
        token_expires_at: new Date(
          Date.now() + Number(tokens.expires_in ?? 3600) * 1000,
        ).toISOString(),
        status: "active",
        last_error_code: null,
      }, { onConflict: "user_id,organization_id,provider,calendar_id" }).select(
        "*",
      ).single();
      if (saved.error || !saved.data) {
        throw new Error("calendar_connection_save_failed");
      }
      await admin.from("sd_calendar_oauth_states").update({
        consumed_at: new Date().toISOString(),
      }).eq("state_hash", stateHash);
      await startWatch(admin, saved.data as Connection, values);
      await queueInitialHomePlateSources(admin, saved.data as Connection);
      await admin.from("sd_calendar_sync_jobs").insert({
        connection_id: saved.data.id,
        organization_id: saved.data.organization_id,
        source_kind: "connection",
        source_id: null,
        operation: "pull",
      });
      return new Response(
        "<!doctype html><title>Home Plate Calendar Connected</title><main style='font-family:system-ui;max-width:36rem;margin:5rem auto;padding:2rem'><h1>Google Calendar connected</h1><p>Return to Home Plate. Your approved schedule will now stay synchronized.</p><script>setTimeout(()=>window.close(),1200)</script></main>",
        { headers: { "content-type": "text/html; charset=utf-8" } },
      );
    }

    if (url.searchParams.get("mode") === "google_webhook") {
      const channelId = text(req.headers.get("x-goog-channel-id"));
      const channelToken = text(req.headers.get("x-goog-channel-token"));
      const connectionResult = await admin.from("sd_calendar_connections")
        .select("*")
        .eq("channel_id", channelId).eq("status", "active").maybeSingle();
      if (
        !connectionResult.data || !channelToken ||
        await sha256Hex(channelToken) !==
          connectionResult.data.channel_token_hash
      ) {
        return json(401, { error: "calendar_webhook_unauthorized" });
      }
      await admin.from("sd_calendar_sync_jobs").insert({
        connection_id: connectionResult.data.id,
        organization_id: connectionResult.data.organization_id,
        source_kind: "connection",
        source_id: null,
        operation: "pull",
      });
      await processWorker(admin, values);
      return json(200, { ok: true });
    }

    if (req.headers.get("x-home-plate-calendar-worker-secret")) {
      if (
        !values.workerSecret ||
        req.headers.get("x-home-plate-calendar-worker-secret") !==
          values.workerSecret
      ) {
        return json(401, { error: "calendar_worker_unauthorized" });
      }
      return json(200, { ok: true, ...(await processWorker(admin, values)) });
    }

    const body = await req.json() as Record<string, unknown>;
    const organizationId = uuid(body.organization_id);
    if (!organizationId) return json(400, { error: "missing_organization_id" });
    const context = await authenticatedContext(req, organizationId);
    const action = text(body.action);

    if (action === "begin_google") {
      const returnURL = allowedReturnURL(text(body.return_url));
      if (!returnURL) {
        return json(400, { error: "calendar_return_url_invalid" });
      }
      const state = randomOpaqueValue(32);
      const verifier = randomOpaqueValue(64);
      await context.admin.from("sd_calendar_oauth_states").delete().eq(
        "user_id",
        context.actorId,
      ).eq("organization_id", organizationId);
      const inserted = await context.admin.from("sd_calendar_oauth_states")
        .insert({
          state_hash: await sha256Hex(state),
          user_id: context.actorId,
          organization_id: organizationId,
          code_verifier_ciphertext: await sealSecret(
            verifier,
            context.values.encryptionKey,
          ),
          return_url: returnURL,
          expires_at: new Date(Date.now() + 10 * 60_000).toISOString(),
        });
      if (inserted.error) throw new Error("calendar_oauth_state_save_failed");
      return json(200, {
        authorization_url: googleAuthorizationURL({
          clientId: context.values.clientId,
          redirectUri: context.values.redirectUri,
          state,
          codeChallenge: await pkceChallenge(verifier),
        }),
      });
    }

    const connectionResult = await context.admin.from("sd_calendar_connections")
      .select("*").eq("user_id", context.actorId).eq(
        "organization_id",
        organizationId,
      )
      .eq("provider", "google").eq("calendar_id", "primary").maybeSingle();
    const connection = connectionResult.data as Connection | null;
    if (action === "status") {
      return json(200, {
        connected: connection?.status === "active",
        status: connection?.status ?? "not_connected",
        last_synced_at: connectionResult.data?.last_synced_at ?? null,
        last_error_code: connectionResult.data?.last_error_code ?? null,
      });
    }
    if (!connection) {
      return json(409, { error: "google_calendar_not_connected" });
    }
    if (action === "disconnect") {
      await context.admin.from("sd_calendar_connections").update({
        status: "disconnected",
        access_token_ciphertext: "revoked",
        refresh_token_ciphertext: null,
        sync_token_ciphertext: null,
        channel_token_hash: null,
      }).eq("id", connection.id);
      return json(200, { ok: true });
    }
    if (action === "sync_now") {
      const changed = await pullLinkedEvents(
        context.admin,
        connection,
        context.values,
      );
      const jobs = await processWorker(context.admin, context.values);
      return json(200, { ok: true, changed, ...jobs });
    }
    return json(400, { error: "unknown_action" });
  } catch (error) {
    const code = safeCalendarError(error);
    const raw = error instanceof Error ? error.message : "calendar_sync_failed";
    const status = raw.includes("auth")
      ? 401
      : raw.includes("membership")
      ? 403
      : raw.includes("configured")
      ? 503
      : 500;
    console.error(
      JSON.stringify({ event: "calendar_integration_failed", code }),
    );
    return json(status, { error: code });
  }
});
