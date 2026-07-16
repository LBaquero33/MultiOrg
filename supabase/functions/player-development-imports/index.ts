import {
  createClient,
  type SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  buildImportStoragePath,
  buildPreview,
  buildValidationPersistencePayload,
  type ColumnMapping,
  decodeImportFile,
  detectProvider,
  type ExternalIdentity,
  headerFingerprint,
  IMPORT_LIMITS,
  IMPORT_MAPPING_VERSION,
  IMPORT_PARSER_VERSION,
  ImportRequestError,
  mappingFingerprint,
  type MetricDefinition,
  parseImportText,
  type PlayerCandidate,
  PROVIDER_ADAPTERS,
  type ProviderKey,
  recommendedMapping,
  sha256Hex,
  stableObservationUUID,
} from "../_shared/player_development_imports.ts";

const BUCKET = "player-development-imports";
const IMPORT_LEASE_MS = 15 * 60_000;
const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const ALLOWED_ACTIONS = new Set([
  "create_job",
  "create_upload_target",
  "inspect_file",
  "get_preview",
  "save_mapping",
  "list_mappings",
  "archive_mapping",
  "resolve_player",
  "validate_job",
  "commit_job",
  "get_job",
  "list_jobs",
  "list_row_errors",
  "archive_job",
]);

type Json = Record<string, unknown>;
type Membership = { role: string; status: string };

function response(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json",
      "cache-control": "no-store",
    },
  });
}

function text(value: unknown, max = 500): string {
  return typeof value === "string" ? value.trim().slice(0, max) : "";
}

function uuid(value: unknown, field: string): string {
  const result = text(value, 36);
  if (!UUID_PATTERN.test(result)) {
    throw new ImportRequestError(
      400,
      `invalid_${field}`,
      `A valid ${field.replaceAll("_", " ")} is required.`,
    );
  }
  return result.toLowerCase();
}

function integer(value: unknown, fallback: number, max: number): number {
  const parsed = Number(value);
  return Number.isInteger(parsed)
    ? Math.max(0, Math.min(parsed, max))
    : fallback;
}

async function readBoundedJSONObject(request: Request): Promise<Json> {
  const declaredLength = Number(request.headers.get("content-length") ?? 0);
  if (
    Number.isFinite(declaredLength) &&
    declaredLength > IMPORT_LIMITS.maxRequestBytes
  ) {
    throw new ImportRequestError(
      413,
      "request_too_large",
      "The import request is too large.",
    );
  }
  if (!request.body) {
    throw new ImportRequestError(
      400,
      "invalid_json",
      "The request body must be valid JSON.",
    );
  }
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  while (true) {
    const { value, done } = await reader.read();
    if (done) break;
    if (!value) continue;
    total += value.byteLength;
    if (total > IMPORT_LIMITS.maxRequestBytes) {
      await reader.cancel();
      throw new ImportRequestError(
        413,
        "request_too_large",
        "The import request is too large.",
      );
    }
    chunks.push(value);
  }
  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  const parsed = JSON.parse(
    new TextDecoder("utf-8", { fatal: true }).decode(bytes),
  );
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new ImportRequestError(
      400,
      "invalid_json",
      "The request body must be a JSON object.",
    );
  }
  return parsed as Json;
}

function extension(fileName: string): "csv" | "tsv" {
  const suffix = fileName.split(".").pop()?.toLowerCase();
  if (suffix !== "csv" && suffix !== "tsv") {
    throw new ImportRequestError(
      400,
      "unsupported_file_type",
      "Export spreadsheet files as CSV or TSV.",
    );
  }
  return suffix;
}

function safeFileName(fileName: string): string {
  const base = fileName.replace(/[\\/\u0000-\u001f]/g, "_").trim().slice(
    0,
    180,
  );
  if (!base) {
    throw new ImportRequestError(
      400,
      "invalid_file_name",
      "A file name is required.",
    );
  }
  extension(base);
  return base;
}

async function authenticate(
  request: Request,
): Promise<{ admin: SupabaseClient; actorId: string }> {
  const url = (Deno.env.get("SUPABASE_URL") ?? "").trim();
  const anon = (Deno.env.get("SUPABASE_ANON_KEY") ?? "").trim();
  const service = (Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "").trim();
  if (!url || !anon || !service) {
    throw new ImportRequestError(
      500,
      "service_unavailable",
      "Import service is not configured.",
    );
  }
  const authorization = request.headers.get("authorization") ?? "";
  if (!authorization.toLowerCase().startsWith("bearer ")) {
    throw new ImportRequestError(
      401,
      "missing_authorization",
      "Sign in to continue.",
    );
  }
  const userClient = createClient(url, anon, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: authorization } },
  });
  const { data, error } = await userClient.auth.getUser();
  if (error || !data.user?.id) {
    throw new ImportRequestError(
      401,
      "invalid_authorization",
      "Your session is no longer valid.",
    );
  }
  return {
    admin: createClient(url, service, {
      auth: { persistSession: false, autoRefreshToken: false },
    }),
    actorId: data.user.id,
  };
}

async function authorizeOrganization(
  admin: SupabaseClient,
  actorId: string,
  orgId: string,
): Promise<Membership> {
  const [{ data: org }, { data: membership }] = await Promise.all([
    admin.from("sd_orgs").select("id,status").eq("id", orgId).maybeSingle(),
    admin.from("sd_org_memberships").select("role,status").eq("org_id", orgId)
      .eq("user_id", actorId).maybeSingle(),
  ]);
  if (
    !org || org.status !== "active" || !membership ||
    membership.status !== "active" ||
    !["owner", "admin", "coach"].includes(membership.role)
  ) {
    throw new ImportRequestError(
      403,
      "organization_staff_required",
      "Active organization staff access is required.",
    );
  }
  return membership as Membership;
}

async function authorizedPlayers(
  admin: SupabaseClient,
  actorId: string,
  orgId: string,
  membership: Membership,
): Promise<PlayerCandidate[]> {
  const { data: activeMemberships } = await admin.from("sd_org_memberships")
    .select("user_id,status,role").eq("org_id", orgId).eq("role", "player").eq(
      "status",
      "active",
    ).limit(10_000);
  let playerIds = (activeMemberships ?? []).map((item: Json) =>
    String(item.user_id)
  );
  if (membership.role === "coach") {
    const { data: settings } = await admin.from("sd_org_settings").select(
      "team_policy",
    ).eq("org_id", orgId).maybeSingle();
    const restricted = (settings?.team_policy as Json | undefined)
      ?.restrictCoachActionsToTeam !== false;
    if (restricted) {
      const { data: actorTeam } = await admin.from("sd_team_members").select(
        "team_id",
      ).eq("org_id", orgId).eq("player_id", actorId).maybeSingle();
      if (!actorTeam?.team_id) playerIds = [];
      else {
        const { data: team } = await admin.from("sd_teams").select("is_active")
          .eq("org_id", orgId).eq("id", actorTeam.team_id).maybeSingle();
        if (!team?.is_active) playerIds = [];
        else {
          const { data: members } = await admin.from("sd_team_members").select(
            "player_id",
          ).eq("org_id", orgId).eq("team_id", actorTeam.team_id).limit(10_000);
          const allowed = new Set(
            (members ?? []).map((item: Json) => String(item.player_id)),
          );
          playerIds = playerIds.filter((id: string) => allowed.has(id));
        }
      }
    }
  }
  if (!playerIds.length) return [];
  const [{ data: profiles }, { data: usernames }] = await Promise.all([
    admin.from("profiles").select("id,full_name").in("id", playerIds).limit(
      10_000,
    ),
    admin.from("sd_org_usernames").select("user_id,username").eq(
      "org_id",
      orgId,
    ).in("user_id", playerIds).limit(10_000),
  ]);
  const usernameByPlayer = new Map(
    (usernames ?? []).map((
      item: Json,
    ) => [String(item.user_id), String(item.username)]),
  );
  return (profiles ?? []).map((profile: Json) => ({
    id: String(profile.id),
    fullName: text(profile.full_name, 200) || "Unnamed player",
    username: usernameByPlayer.get(String(profile.id)) ?? null,
    active: true,
  }));
}

async function scopedJob(
  admin: SupabaseClient,
  orgId: string,
  jobId: string,
): Promise<Json> {
  const { data } = await admin.from("sd_development_import_jobs").select("*")
    .eq("id", jobId).eq("org_id", orgId).maybeSingle();
  if (!data) {
    throw new ImportRequestError(
      404,
      "import_job_not_found",
      "The import job was not found.",
    );
  }
  return data as Json;
}

async function ensureJobPlayerScope(
  job: Json,
  players: PlayerCandidate[],
  membership?: Membership,
  actorId?: string,
): Promise<void> {
  const playerId = job.player_id ? String(job.player_id) : null;
  if (playerId && !players.some((player) => player.id === playerId)) {
    throw new ImportRequestError(
      403,
      "player_scope_denied",
      "This import is outside your player scope.",
    );
  }
  if (
    !playerId && membership?.role === "coach" &&
    String(job.requested_by) !== actorId
  ) {
    throw new ImportRequestError(
      403,
      "import_job_scope_denied",
      "Organization-wide coach imports are visible only to their creator.",
    );
  }
}

function assertJobStatus(job: Json, allowed: string[], action: string): void {
  if (!allowed.includes(String(job.status))) {
    throw new ImportRequestError(
      409,
      "invalid_job_transition",
      `This import cannot be ${action} from its current state.`,
    );
  }
}

async function playerScopeFingerprint(
  players: PlayerCandidate[],
): Promise<string> {
  return await sha256Hex(
    players.map((player) => player.id).sort().join("\u001f"),
  );
}

async function equivalentCompletedJob(
  admin: SupabaseClient,
  job: Json,
): Promise<Json | null> {
  if (
    !job.file_sha256 || !job.mapping_fingerprint ||
    !job.player_scope_fingerprint
  ) {
    return null;
  }
  const { data } = await admin.from("sd_development_import_jobs").select("*")
    .eq("org_id", job.org_id)
    .eq("provider", job.provider)
    .eq("file_sha256", job.file_sha256)
    .eq("parser_version", job.parser_version)
    .eq("mapping_fingerprint", job.mapping_fingerprint)
    .eq("player_scope_fingerprint", job.player_scope_fingerprint)
    .in("status", ["completed", "completed_with_errors"])
    .neq("id", job.id)
    .order("completed_at", { ascending: true })
    .limit(1)
    .maybeSingle();
  return data as Json | null;
}

async function downloadAuthoritative(
  admin: SupabaseClient,
  job: Json,
): Promise<
  {
    bytes: Uint8Array;
    parsed: ReturnType<typeof parseImportText>;
    digest: string;
  }
> {
  if (
    !job.artifact_expires_at ||
    new Date(String(job.artifact_expires_at)).valueOf() <= Date.now()
  ) {
    throw new ImportRequestError(
      410,
      "import_artifact_expired",
      "This private import artifact has expired. Create a new import job.",
    );
  }
  if (job.storage_bucket !== BUCKET || typeof job.storage_path !== "string") {
    throw new ImportRequestError(
      409,
      "upload_required",
      "Upload the selected file before inspection.",
    );
  }
  const { data, error } = await admin.storage.from(BUCKET).download(
    job.storage_path,
  );
  if (error || !data) {
    throw new ImportRequestError(
      409,
      "upload_not_found",
      "The private upload could not be found.",
    );
  }
  if (data.size > IMPORT_LIMITS.maxFileBytes) {
    throw new ImportRequestError(
      413,
      "file_too_large",
      "CSV and TSV files must be 10 MB or smaller.",
    );
  }
  const bytes = new Uint8Array(await data.arrayBuffer());
  const decoded = decodeImportFile(bytes);
  const parsed = parseImportText(decoded, extension(String(job.file_name)));
  const digest = await sha256Hex(bytes);
  if (job.file_sha256 && job.file_sha256 !== digest) {
    throw new ImportRequestError(
      409,
      "file_identity_changed",
      "The uploaded file no longer matches the inspected file.",
    );
  }
  return { bytes, parsed, digest };
}

async function loadPreview(
  admin: SupabaseClient,
  actorId: string,
  orgId: string,
  membership: Membership,
  job: Json,
): Promise<Awaited<ReturnType<typeof preparePreview>>> {
  const players = await authorizedPlayers(admin, actorId, orgId, membership);
  await ensureJobPlayerScope(job, players, membership, actorId);
  const effectivePlayers = job.player_id
    ? players.filter((player) => player.id === String(job.player_id))
    : players;
  return await preparePreview(admin, orgId, job, effectivePlayers);
}

async function preparePreview(
  admin: SupabaseClient,
  orgId: string,
  job: Json,
  players: PlayerCandidate[],
) {
  const authoritative = await downloadAuthoritative(admin, job);
  const mapping = job.mapping_config as ColumnMapping;
  const [{ data: definitions }, { data: externalRows }] = await Promise.all([
    admin.from("sd_development_metric_definitions")
      .select(
        "id,canonical_key,display_name,category,canonical_unit,preferred_direction,minimum_sample_size,status",
      )
      .in("status", ["active", "deprecated"])
      .in("data_type", ["number", "duration"]).limit(500),
    admin.from("sd_development_external_player_identities")
      .select("provider,external_player_id,player_id").eq("org_id", orgId).is(
        "archived_at",
        null,
      ).limit(10_000),
  ]);
  const identities: ExternalIdentity[] = (externalRows ?? []).map((
    row: Json,
  ) => ({
    provider: String(row.provider),
    externalPlayerId: String(row.external_player_id),
    playerId: String(row.player_id),
  }));
  const preview = buildPreview({
    parsed: authoritative.parsed,
    provider: String(job.provider ?? "generic_csv") as ProviderKey,
    mapping,
    definitions: (definitions ?? []) as MetricDefinition[],
    players,
    identities,
  });
  return {
    ...authoritative,
    ...preview,
    definitions: (definitions ?? []) as MetricDefinition[],
    players,
    playerScopeFingerprint: await playerScopeFingerprint(players),
  };
}

function validationPersistenceStage(error: {
  code?: string;
  message?: string;
}): string {
  const safeMessage = String(error.message ?? "");
  if (safeMessage.includes("validation_scope_failed")) {
    return "validation_scope_failed";
  }
  if (safeMessage.includes("validation_input_changed")) {
    return "validation_input_changed";
  }
  if (safeMessage.includes("validation_summary_constraint_failed")) {
    return "validation_summary_constraint_failed";
  }
  if (safeMessage.includes("validation_transition_failed")) {
    return "validation_transition_failed";
  }
  if (
    safeMessage.includes("validation_row_error_replace_failed") ||
    error.code === "23505"
  ) {
    return "validation_row_error_replace_failed";
  }
  return "validation_persistence_failed";
}

async function persistValidation(
  admin: SupabaseClient,
  actorId: string,
  orgId: string,
  job: Json,
  preview: Awaited<ReturnType<typeof preparePreview>>,
) {
  const persistence = buildValidationPersistencePayload(
    preview.rows,
    preview.summary,
  );
  const expectedMappingFingerprint = await mappingFingerprint(
    job.mapping_config as ColumnMapping,
  );
  const result = await admin.rpc(
    "sd_persist_development_import_validation",
    {
      p_actor_id: actorId,
      p_org_id: orgId,
      p_job_id: String(job.id),
      p_expected_file_sha256: preview.digest,
      p_expected_mapping_fingerprint: expectedMappingFingerprint,
      p_expected_player_scope_fingerprint: preview.playerScopeFingerprint,
      p_row_count: preview.summary.totalRows,
      p_accepted_rows: preview.summary.acceptedRows,
      p_rejected_rows: preview.summary.rejectedRows,
      p_unmatched_player_rows: preview.summary.unmatchedPlayerRows,
      p_ambiguous_player_rows: preview.summary.ambiguousPlayerRows,
      p_warning_count: preview.summary.warningCount,
      p_validation_summary: persistence.validationSummary,
      p_row_errors: persistence.rowErrors,
    },
  );
  if (result.error) {
    const internalStage = validationPersistenceStage(result.error);
    const inputChanged = internalStage === "validation_input_changed";
    const safeCode = inputChanged
      ? "validation_input_changed"
      : "validation_persistence_failed";
    const safeMessage = inputChanged
      ? "The file, mapping, or player access changed during validation. Start Over to create a fresh import."
      : "Validation details could not be saved. Resume Validation to retry safely.";
    await admin.from("sd_development_import_jobs").update({
      safe_error_code: safeCode,
      safe_error_summary: safeMessage,
    }).eq("id", String(job.id)).eq("org_id", orgId).in("status", [
      "validating",
      "player_resolution_required",
      "ready",
    ]);
    throw new ImportRequestError(
      inputChanged ? 409 : 500,
      safeCode,
      safeMessage,
      internalStage,
      text(result.error.code, 20) || undefined,
      result.status,
    );
  }
  const status = (result.data as Json | null)?.status;
  if (status !== "ready" && status !== "player_resolution_required") {
    throw new ImportRequestError(
      500,
      "validation_persistence_failed",
      "Validation details could not be saved. Resume Validation to retry safely.",
      "validation_persistence_result_failed",
    );
  }
  return status;
}

async function handleAction(
  admin: SupabaseClient,
  actorId: string,
  body: Json,
): Promise<unknown> {
  const action = text(body.action, 40);
  if (!ALLOWED_ACTIONS.has(action)) {
    throw new ImportRequestError(
      400,
      "unsupported_action",
      "The requested import action is not supported.",
    );
  }
  const orgId = uuid(body.org_id, "organization_id");
  const membership = await authorizeOrganization(admin, actorId, orgId);
  const players = await authorizedPlayers(admin, actorId, orgId, membership);

  if (action === "create_job") {
    const fileName = safeFileName(text(body.file_name, 200));
    const fileType = extension(fileName);
    const provider = (text(body.provider, 40) || "generic_csv") as ProviderKey;
    if (!PROVIDER_ADAPTERS[provider]) {
      throw new ImportRequestError(
        400,
        "unsupported_provider",
        "Choose a supported import provider.",
      );
    }
    // Non-generic labels remain manual; automatic adapters are not activated.
    const playerId = body.player_id ? uuid(body.player_id, "player_id") : null;
    if (playerId && !players.some((player) => player.id === playerId)) {
      throw new ImportRequestError(
        403,
        "player_scope_denied",
        "This player is outside your scope.",
      );
    }
    if (!playerId && membership.role === "coach" && !players.length) {
      throw new ImportRequestError(
        403,
        "player_scope_denied",
        "A coach needs at least one authorized player for a multi-player import.",
      );
    }
    const effectivePlayers = playerId
      ? players.filter((player) => player.id === playerId)
      : players;
    const idempotencyKey = body.idempotency_key
      ? uuid(body.idempotency_key, "idempotency_key")
      : crypto.randomUUID();
    const { data: existingIdempotent } = await admin.from(
      "sd_development_import_jobs",
    ).select("*").eq("org_id", orgId).eq("requested_by", actorId).eq(
      "idempotency_key",
      idempotencyKey,
    ).maybeSingle();
    if (existingIdempotent) {
      const sameRequest = existingIdempotent.file_name === fileName &&
        existingIdempotent.provider === provider &&
        (existingIdempotent.player_id ?? null) === playerId;
      if (!sameRequest) {
        throw new ImportRequestError(
          409,
          "idempotency_key_conflict",
          "That request key was already used for different import parameters.",
        );
      }
      if (
        existingIdempotent.status !== "pending" ||
        new Date(String(existingIdempotent.artifact_expires_at)).valueOf() <=
          Date.now()
      ) {
        throw new ImportRequestError(
          409,
          "idempotent_import_already_started",
          "This import request already progressed. Resume its existing job.",
        );
      }
      return {
        job: existingIdempotent,
        upload: {
          bucket: BUCKET,
          path: existingIdempotent.storage_path,
          max_file_bytes: IMPORT_LIMITS.maxFileBytes,
          upsert: false,
        },
        reused: true,
      };
    }
    const jobId = crypto.randomUUID();
    const objectId = crypto.randomUUID();
    const storagePath = buildImportStoragePath(
      orgId,
      jobId,
      objectId,
      fileType,
    );
    const { data, error } = await admin.from("sd_development_import_jobs")
      .insert({
        id: jobId,
        org_id: orgId,
        player_id: playerId,
        requested_by: actorId,
        import_source: "private_storage",
        provider,
        file_name: fileName,
        original_file_type: fileType,
        storage_bucket: BUCKET,
        storage_path: storagePath,
        status: "pending",
        idempotency_key: idempotencyKey,
        import_version: "player-development-import.v1",
        parser_version: IMPORT_PARSER_VERSION,
        player_scope_fingerprint: await playerScopeFingerprint(
          effectivePlayers,
        ),
        artifact_expires_at: new Date(Date.now() + 30 * 86400_000)
          .toISOString(),
      }).select("*").single();
    if (error || !data) {
      throw new ImportRequestError(
        409,
        "job_create_failed",
        "A new import job could not be created.",
      );
    }
    return {
      job: data,
      upload: {
        bucket: BUCKET,
        path: storagePath,
        max_file_bytes: IMPORT_LIMITS.maxFileBytes,
        upsert: false,
      },
    };
  }

  const jobId = uuid(body.job_id, "job_id");
  const job = await scopedJob(admin, orgId, jobId);
  await ensureJobPlayerScope(job, players, membership, actorId);

  if (action === "create_upload_target") {
    if (job.status !== "pending") {
      throw new ImportRequestError(
        409,
        "upload_already_started",
        "This job is no longer accepting an upload.",
      );
    }
    if (
      !job.artifact_expires_at ||
      new Date(String(job.artifact_expires_at)).valueOf() <= Date.now()
    ) {
      throw new ImportRequestError(
        410,
        "upload_target_expired",
        "This upload target has expired. Create a new import job.",
      );
    }
    return {
      bucket: job.storage_bucket,
      path: job.storage_path,
      max_file_bytes: IMPORT_LIMITS.maxFileBytes,
      upsert: false,
    };
  }

  if (action === "inspect_file") {
    assertJobStatus(
      job,
      ["pending", "failed", "mapping_required"],
      "inspected",
    );
    if (job.status !== "mapping_required") {
      await admin.from("sd_development_import_jobs").update({
        status: "inspecting",
        started_at: job.started_at ?? new Date().toISOString(),
      }).eq("id", jobId).eq("org_id", orgId);
    }
    const authoritative = await downloadAuthoritative(admin, job);
    const detection = detectProvider(authoritative.parsed);
    const fingerprint = await headerFingerprint(authoritative.parsed.headers);
    const automaticMapping = recommendedMapping(
      authoritative.parsed,
      detection,
      "UTC",
    );
    const protectedHeaders = new Set(
      detection.protectedColumns.map((header) =>
        header.trim().toLocaleLowerCase("en-US")
      ),
    );
    let data: Json = job;
    let error = null;
    if (job.status !== "mapping_required") {
      const updateResult = await admin.from("sd_development_import_jobs")
        .update({
          status: "mapping_required",
          file_sha256: authoritative.digest,
          file_size_bytes: authoritative.bytes.byteLength,
          original_file_type: authoritative.parsed.fileType,
          row_count: authoritative.parsed.totalRows,
          header_fingerprint: fingerprint,
          provider: detection.providerKey,
          detected_export_type: detection.exportType,
          adapter_version: detection.adapterVersion,
          detection_confidence: detection.confidence,
          detection_metadata: {
            matched_required_signatures: detection.matchedRequiredSignatures,
            matched_optional_signatures: detection.matchedOptionalSignatures,
            missing_signatures: detection.missingSignatures,
            warnings: detection.warnings,
            protected_columns: detection.protectedColumns,
            unsupported_columns: detection.unsupportedColumns,
            automatic_mapping_safe: detection.automaticMappingSafe,
          },
          parser_version: detection.adapterVersion,
          validation_summary: {
            blank_rows_ignored: authoritative.parsed.blankRows,
            delimiter: authoritative.parsed.delimiter,
          },
        }).eq("id", jobId).eq("org_id", orgId).select("*").single();
      data = updateResult.data as Json;
      error = updateResult.error;
    }
    if (error) {
      throw new ImportRequestError(
        500,
        "inspection_update_failed",
        "Inspection could not be saved.",
      );
    }
    return {
      job: data,
      inspection: {
        detected_file_type: authoritative.parsed.fileType,
        detected_delimiter: authoritative.parsed.delimiter === "\t"
          ? "tab"
          : "comma",
        headers: authoritative.parsed.headers,
        normalized_headers: authoritative.parsed.normalizedHeaders,
        row_count: authoritative.parsed.totalRows,
        preview_rows: authoritative.parsed.rows.slice(0, 10).map((row) =>
          row.map((cell, index) =>
            protectedHeaders.has(
                authoritative.parsed.headers[index]?.trim()
                  .toLocaleLowerCase("en-US"),
              )
              ? ""
              : cell.slice(0, 200)
          )
        ),
        warnings: authoritative.parsed.warnings,
        header_fingerprint: fingerprint,
        provider_adapter_active: PROVIDER_ADAPTERS[detection.providerKey]
          ?.productionActive === true,
        detection: {
          provider_key: detection.providerKey,
          export_type: detection.exportType,
          adapter_version: detection.adapterVersion,
          confidence: detection.confidence,
          matched_required_signatures: detection.matchedRequiredSignatures,
          matched_optional_signatures: detection.matchedOptionalSignatures,
          missing_signatures: detection.missingSignatures,
          warnings: detection.warnings,
          automatic_mapping_safe: detection.automaticMappingSafe,
          protected_columns: detection.protectedColumns,
          unsupported_columns: detection.unsupportedColumns,
          provider_player_id: detection.providerPlayerId,
          provider_player_name: detection.providerPlayerName,
        },
        suggested_mapping: automaticMapping,
      },
    };
  }

  if (action === "save_mapping") {
    assertJobStatus(
      job,
      [
        "mapping_required",
        "validating",
        "player_resolution_required",
        "ready",
        "failed",
      ],
      "mapped",
    );
    const authoritative = await downloadAuthoritative(admin, job);
    const mapping = body.mapping as ColumnMapping;
    if (
      job.detected_export_type !== "generic_csv" && job.adapter_version &&
      mapping.adapterVersion !== job.adapter_version
    ) {
      throw new ImportRequestError(
        409,
        "adapter_version_changed",
        "Refresh this import before applying mappings from another adapter version.",
      );
    }
    // buildPreview performs structural validation without writing observations.
    const definitionsResult = await admin.from(
      "sd_development_metric_definitions",
    ).select(
      "id,canonical_key,display_name,category,canonical_unit,preferred_direction,minimum_sample_size,status",
    ).in("data_type", ["number", "duration"]).limit(500);
    buildPreview({
      parsed: authoritative.parsed,
      provider: String(job.provider) as ProviderKey,
      mapping,
      definitions: (definitionsResult.data ?? []) as MetricDefinition[],
      players,
      identities: [],
    });
    const fingerprint = await mappingFingerprint(mapping);
    const mappingVersion = `${IMPORT_MAPPING_VERSION}:${
      fingerprint.slice(0, 12)
    }`;
    const { data, error } = await admin.from("sd_development_import_jobs")
      .update({
        mapping_config: mapping,
        mapping_fingerprint: fingerprint,
        mapping_version: mappingVersion,
        unit_system: mapping.unitSystem ?? null,
        import_timezone: mapping.timezone,
        file_shape: mapping.shape,
        status: "validating",
      }).eq("id", jobId).eq("org_id", orgId).select("*").single();
    if (error) {
      throw new ImportRequestError(
        500,
        "mapping_save_failed",
        "The mapping could not be saved.",
      );
    }
    let profile = null;
    const profileName = text(body.mapping_name, 100);
    if (profileName) {
      const reusableMapping: ColumnMapping = {
        ...mapping,
        playerResolutions: {},
      };
      const reusableFingerprint = await mappingFingerprint(reusableMapping);
      const reusableMappingVersion = `${IMPORT_MAPPING_VERSION}:${
        reusableFingerprint.slice(0, 12)
      }`;
      const headerHash = String(
        job.header_fingerprint ||
          await headerFingerprint(authoritative.parsed.headers),
      );
      const sections = mapping as unknown as Json;
      const profileResult = await admin.from(
        "sd_development_import_mapping_profiles",
      ).insert({
        org_id: orgId,
        provider: job.provider,
        mapping_name: profileName,
        header_fingerprint: headerHash,
        normalized_headers: authoritative.parsed.normalizedHeaders,
        parser_version: String(job.parser_version || IMPORT_PARSER_VERSION),
        mapping_version: reusableMappingVersion,
        file_shape: mapping.shape,
        player_mapping: {
          columns: mapping.columns,
          resolutions: {},
        },
        date_mapping: {
          timezone: mapping.timezone,
          date_format: mapping.dateFormat,
          columns: mapping.columns,
        },
        metric_mapping: {
          wide_metrics: mapping.wideMetrics ?? [],
          long_metric_keys: mapping.longMetricKeys ?? {},
        },
        unit_mapping: { long_source_units: mapping.longSourceUnits ?? {} },
        context_mapping: { columns: mapping.contextColumns ?? [] },
        mapping_config: reusableMapping,
        created_by: actorId,
      }).select("*").single();
      if (profileResult.error) {
        throw new ImportRequestError(
          409,
          "mapping_profile_conflict",
          "An active mapping with that name already exists.",
        );
      }
      profile = profileResult.data;
      void sections;
    }
    return { job: data, mapping_profile: profile };
  }

  if (action === "resolve_player") {
    assertJobStatus(
      job,
      ["validating", "player_resolution_required", "ready", "failed"],
      "resolved",
    );
    const sourceKey = text(body.source_key, 300);
    const playerId = uuid(body.player_id, "player_id");
    if (!sourceKey || !players.some((player) => player.id === playerId)) {
      throw new ImportRequestError(
        403,
        "player_scope_denied",
        "Choose an active player in your scope.",
      );
    }
    const currentPreview = await loadPreview(
      admin,
      actorId,
      orgId,
      membership,
      job,
    );
    const sourceRow = currentPreview.rows.find((row) =>
      row.playerSourceKey === sourceKey
    );
    if (!sourceRow) {
      throw new ImportRequestError(
        409,
        "player_resolution_source_changed",
        "That player identity is no longer present in the authoritative file.",
      );
    }
    const mapping = (job.mapping_config ?? {}) as ColumnMapping;
    mapping.playerResolutions = {
      ...(mapping.playerResolutions ?? {}),
      [sourceKey]: playerId,
    };
    if (sourceKey.startsWith("external:")) {
      const externalId = text(sourceKey.slice("external:".length), 200);
      const { data: providerIdentities, error: identityReadError } = await admin
        .from(
          "sd_development_external_player_identities",
        )
        .select("id,player_id,external_player_id")
        .eq("org_id", orgId)
        .eq("provider", job.provider)
        .is("archived_at", null)
        .limit(10_000);
      const existingIdentity = providerIdentities?.find((identity: Json) =>
        String(identity.external_player_id ?? "").trim().toLocaleLowerCase(
          "en-US",
        ) === externalId.trim().toLocaleLowerCase("en-US")
      );
      if (
        identityReadError ||
        (existingIdentity && existingIdentity.player_id !== playerId)
      ) {
        throw new ImportRequestError(
          409,
          "external_identity_conflict",
          "That provider ID is already linked.",
        );
      }
      const identityWrite = existingIdentity
        ? await admin.from("sd_development_external_player_identities").update({
          display_label: sourceRow.playerLabel.slice(0, 200) || null,
          verification_state: "staff_verified",
          linked_by: actorId,
        }).eq("id", existingIdentity.id)
        : await admin.from(
          "sd_development_external_player_identities",
        ).insert({
          org_id: orgId,
          provider: job.provider,
          external_player_id: externalId,
          player_id: playerId,
          display_label: sourceRow.playerLabel.slice(0, 200) || null,
          verification_state: "staff_verified",
          linked_by: actorId,
          archived_at: null,
        });
      if (identityWrite.error) {
        throw new ImportRequestError(
          409,
          "external_identity_conflict",
          "That provider ID is already linked.",
        );
      }
    }
    const fingerprint = await mappingFingerprint(mapping);
    const { data, error } = await admin.from("sd_development_import_jobs")
      .update({
        mapping_config: mapping,
        mapping_fingerprint: fingerprint,
        mapping_version: `${IMPORT_MAPPING_VERSION}:${
          fingerprint.slice(0, 12)
        }`,
        status: "validating",
      }).eq("id", jobId).eq("org_id", orgId).select("*").single();
    if (error) {
      throw new ImportRequestError(
        500,
        "player_resolution_failed",
        "The player resolution could not be saved.",
      );
    }
    return { job: data };
  }

  if (action === "get_preview" || action === "validate_job") {
    assertJobStatus(
      job,
      ["validating", "player_resolution_required", "ready"],
      action === "validate_job" ? "validated" : "previewed",
    );
    const preview = await loadPreview(admin, actorId, orgId, membership, job);
    const status = action === "validate_job"
      ? await persistValidation(admin, actorId, orgId, job, preview)
      : job.status;
    const filter = text(body.filter, 30);
    const filtered = filter
      ? preview.rows.filter((row) =>
        filter === "unmatched"
          ? row.playerMatchState === "unmatched"
          : filter === "ambiguous"
          ? row.playerMatchState === "ambiguous"
          : row.acceptanceState === filter
      )
      : preview.rows;
    return {
      notice: "Preview only — no player development data has been imported.",
      status,
      summary: preview.summary,
      rows: filtered.slice(
        0,
        integer(
          body.limit,
          IMPORT_LIMITS.previewRows,
          IMPORT_LIMITS.previewRows,
        ),
      ),
      detected_file_type: preview.parsed.fileType,
      detected_delimiter: preview.parsed.delimiter === "\t" ? "tab" : "comma",
      headers: preview.parsed.headers,
      player_candidates: preview.players.slice(0, 1_000).map((player) => ({
        id: player.id,
        full_name: player.fullName,
        username: player.username ?? null,
      })),
      player_candidates_truncated: preview.players.length > 1_000,
    };
  }

  if (action === "commit_job") {
    if (["completed", "completed_with_errors"].includes(String(job.status))) {
      return { job, reused: true };
    }
    if (
      job.status === "failed" && job.safe_error_code === "duplicate_file_reused"
    ) {
      const winner = await equivalentCompletedJob(admin, job);
      if (winner) return { job: winner, reused: true };
    }
    const staleImport = String(job.status) === "importing" &&
      Date.now() - new Date(String(job.updated_at)).valueOf() >=
        IMPORT_LEASE_MS;
    if (job.status !== "ready" && !staleImport) {
      throw new ImportRequestError(
        409,
        "job_not_ready",
        "Validate the import before confirming it.",
      );
    }
    const existingCompleted = await equivalentCompletedJob(admin, job);
    if (existingCompleted) {
      await admin.from("sd_development_import_jobs").update({
        status: "failed",
        completed_at: new Date().toISOString(),
        safe_error_code: "duplicate_file_reused",
        safe_error_summary: "An equivalent completed import was reused.",
      }).eq("id", jobId).eq("org_id", orgId).eq("status", job.status);
      return { job: existingCompleted, reused: true };
    }
    const preview = await loadPreview(admin, actorId, orgId, membership, job);
    if (preview.digest !== job.file_sha256) {
      throw new ImportRequestError(
        409,
        "file_identity_changed",
        "The uploaded file changed after preview.",
      );
    }
    if (preview.playerScopeFingerprint !== job.player_scope_fingerprint) {
      throw new ImportRequestError(
        409,
        "player_scope_changed",
        "Player access changed after validation. Validate the import again.",
      );
    }
    const rejected = preview.rows.filter((row) => row.errors.length > 0);
    const accepted = preview.rows.filter((row) =>
      row.errors.length === 0 && row.playerId && row.metricKey && row.observedAt
    );
    if (!accepted.length) {
      throw new ImportRequestError(
        409,
        "no_accepted_observations",
        "Resolve validation errors before importing; no observations are accepted.",
      );
    }
    let claimQuery = admin.from("sd_development_import_jobs").update({
      status: "importing",
    }).eq("id", jobId).eq("org_id", orgId);
    claimQuery = staleImport
      ? claimQuery.eq("status", "importing").eq("updated_at", job.updated_at)
      : claimQuery.eq("status", "ready");
    const claim = await claimQuery.select("id");
    if (claim.error || !claim.data?.length) {
      const current = await scopedJob(admin, orgId, jobId);
      if (
        ["completed", "completed_with_errors"].includes(String(current.status))
      ) return { job: current, reused: true };
      throw new ImportRequestError(
        409,
        "concurrent_commit",
        "This import is already being committed.",
      );
    }
    const definitions = new Map(
      preview.definitions.map((
        definition,
      ) => [definition.canonical_key, definition]),
    );
    const observations = await Promise.all(accepted.map(async (row) => {
      const definition = definitions.get(row.metricKey!);
      const material = [
        orgId,
        String(job.provider || "generic_csv"),
        preview.digest,
        String(job.parser_version),
        String(job.mapping_fingerprint),
        row.sourceRowNumber,
        row.sourceEventId,
        row.playerId,
        row.metricKey,
        row.originalValue,
        row.originalUnit,
        row.observedAt,
      ].join("|");
      return {
        org_id: orgId,
        player_id: row.playerId,
        metric_definition_id: definition!.id,
        observed_value: row.originalValue,
        normalized_value: row.normalizedValue,
        unit: row.canonicalUnit,
        original_unit: row.originalUnit || null,
        canonical_unit: row.canonicalUnit,
        observed_at: row.observedAt,
        source_system: String(job.provider || "generic_csv"),
        source_entity_type: "player_development_import",
        source_record_id: await stableObservationUUID(material),
        import_job_id: jobId,
        context_metadata: {
          ...row.context,
          import_job_id: jobId,
          adapter_version: String(job.adapter_version || job.parser_version),
          detected_export_type: String(
            job.detected_export_type || "generic_csv",
          ),
          verification_status: "device_imported_unverified",
          original_unit: row.originalUnit || null,
          canonical_unit: row.canonicalUnit,
        },
        quality_status: "sufficient",
        sample_size: row.sampleSize,
        conversion_rule: row.conversionRule,
        conversion_version: row.conversionVersion,
        verification_status: "device_imported_unverified",
        parser_version: job.parser_version,
        mapping_version: job.mapping_version,
        adapter_version: String(job.adapter_version || job.parser_version),
        provider_export_type: String(job.detected_export_type || "generic_csv"),
        source_row_number: row.sourceRowNumber,
        source_date_string: row.sourceDateString,
        imported_timezone: (job.mapping_config as ColumnMapping).timezone,
      };
    }));
    if (observations.length) {
      const { error } = await admin.from("sd_player_metric_observations")
        .upsert(observations, {
          onConflict:
            "org_id,player_id,metric_definition_id,source_system,source_entity_type,source_record_id,observed_at",
          ignoreDuplicates: true,
        });
      if (error) {
        await admin.from("sd_development_import_jobs").update({
          status: "failed",
          safe_error_code: "observation_commit_failed",
          safe_error_summary: "Validated observations could not be committed.",
        }).eq("id", jobId).eq("org_id", orgId);
        throw new ImportRequestError(
          500,
          "observation_commit_failed",
          "Validated observations could not be committed.",
        );
      }
    }
    const summary = {
      ...preview.summary,
      accepted_observations: accepted.length,
      rejected_observations: rejected.length,
      persisted_row_errors: Math.min(
        preview.rows.filter((row) => row.acceptanceState !== "accepted").length,
        IMPORT_LIMITS.maxPersistedRowErrors,
      ),
      row_errors_truncated: preview.rows.filter((row) =>
        row.acceptanceState !== "accepted"
      )
        .length > IMPORT_LIMITS.maxPersistedRowErrors,
    };
    const finalStatus = rejected.length ? "completed_with_errors" : "completed";
    const { data: completed, error } = await admin.from(
      "sd_development_import_jobs",
    ).update({
      status: finalStatus,
      accepted_rows: preview.summary.acceptedRows,
      rejected_rows: preview.summary.rejectedRows,
      unmatched_player_rows: preview.summary.unmatchedPlayerRows,
      warning_count: preview.summary.warningCount,
      validation_summary: summary,
      completed_at: new Date().toISOString(),
      safe_error_code: null,
      safe_error_summary: null,
    }).eq("id", jobId).eq("org_id", orgId).select("*").single();
    if (error) {
      const winner = await equivalentCompletedJob(admin, job);
      if (winner) {
        await admin.from("sd_development_import_jobs").update({
          status: "failed",
          completed_at: new Date().toISOString(),
          safe_error_code: "duplicate_file_reused",
          safe_error_summary:
            "An equivalent import completed concurrently; its result was reused.",
        }).eq("id", jobId).eq("org_id", orgId).eq("status", "importing");
        return { job: winner, reused: true };
      }
      throw new ImportRequestError(
        500,
        "commit_finalize_failed",
        "The observations were saved but job finalization requires support review.",
      );
    }
    return {
      job: completed,
      result: summary,
      reused: false,
      automatic_actions: {
        reports: false,
        alerts: false,
        notifications: false,
        apns: false,
      },
    };
  }

  if (action === "get_job") return { job };
  if (action === "archive_job") {
    const restartable = [
      "pending",
      "uploaded",
      "inspecting",
      "mapping_required",
      "player_resolution_required",
      "validating",
      "ready",
    ].includes(String(job.status));
    const normallyArchivable = [
      "completed",
      "completed_with_errors",
      "failed",
    ].includes(String(job.status));
    if (!restartable && !normallyArchivable) {
      throw new ImportRequestError(
        409,
        "job_not_archivable",
        "Only incomplete or finished imports can be archived.",
      );
    }
    const archiveResult = await admin.rpc(
      "sd_archive_development_import_job",
      {
        p_actor_id: actorId,
        p_org_id: orgId,
        p_job_id: jobId,
        p_for_restart: restartable,
      },
    );
    if (archiveResult.error) {
      throw new ImportRequestError(
        restartable ? 409 : 500,
        restartable ? "start_over_failed" : "archive_failed",
        restartable
          ? "The incomplete import could not be archived. Resume Validation if it is still available."
          : "The import could not be archived.",
      );
    }
    return { job: await scopedJob(admin, orgId, jobId) };
  }
  if (action === "list_row_errors") {
    const limit = integer(body.limit, 100, 500);
    const { data, error } = await admin.from("sd_development_import_row_errors")
      .select("*").eq("org_id", orgId).eq("import_job_id", jobId).order(
        "source_row_number",
      ).limit(limit);
    if (error) {
      throw new ImportRequestError(
        500,
        "row_errors_unavailable",
        "Import errors could not be loaded.",
      );
    }
    return { errors: data ?? [] };
  }
  throw new ImportRequestError(
    400,
    "unsupported_action",
    "The requested import action is not supported.",
  );
}

async function handleCollectionAction(
  admin: SupabaseClient,
  actorId: string,
  body: Json,
): Promise<unknown> {
  const action = text(body.action, 40);
  const orgId = uuid(body.org_id, "organization_id");
  const membership = await authorizeOrganization(admin, actorId, orgId);
  void membership;
  if (action === "list_jobs") {
    const limit = integer(body.limit, 50, 200);
    const { data, error } = await admin.from("sd_development_import_jobs")
      .select("*").eq("org_id", orgId).order("created_at", { ascending: false })
      .limit(membership.role === "coach" ? 1_000 : limit);
    if (error) {
      throw new ImportRequestError(
        500,
        "jobs_unavailable",
        "Import history could not be loaded.",
      );
    }
    if (membership.role !== "coach") return { jobs: data ?? [] };
    const players = await authorizedPlayers(admin, actorId, orgId, membership);
    const allowed = new Set(players.map((player) => player.id));
    const scoped = (data ?? []).filter((job: Json) =>
      job.player_id
        ? allowed.has(String(job.player_id))
        : String(job.requested_by) === actorId
    ).slice(0, limit);
    return { jobs: scoped };
  }
  if (action === "list_mappings") {
    const provider = text(body.provider, 40);
    let query = admin.from("sd_development_import_mapping_profiles").select("*")
      .eq("org_id", orgId).eq("is_active", true).order("mapping_name").limit(
        200,
      );
    if (provider) query = query.eq("provider", provider);
    const { data, error } = await query;
    if (error) {
      throw new ImportRequestError(
        500,
        "mappings_unavailable",
        "Saved mappings could not be loaded.",
      );
    }
    return { mappings: data ?? [] };
  }
  if (action === "archive_mapping") {
    const profileId = uuid(body.mapping_profile_id, "mapping_profile_id");
    const { data, error } = await admin.from(
      "sd_development_import_mapping_profiles",
    ).update({
      is_active: false,
      archived_at: new Date().toISOString(),
    }).eq("id", profileId).eq("org_id", orgId).eq("is_active", true).select(
      "*",
    ).single();
    if (error || !data) {
      throw new ImportRequestError(
        404,
        "mapping_profile_not_found",
        "That active mapping profile is not available.",
      );
    }
    return { mapping: data };
  }
  return await handleAction(admin, actorId, body);
}

Deno.serve(async (request) => {
  const forwardedRequestId = text(
    request.headers.get("x-request-id") ?? request.headers.get("sb-request-id"),
    36,
  );
  const requestId = UUID_PATTERN.test(forwardedRequestId)
    ? forwardedRequestId.toLowerCase()
    : crypto.randomUUID();
  let logAction = "";
  let logOrgId = "";
  let logJobId = "";
  if (request.method !== "POST") {
    return response(405, {
      error: {
        code: "method_not_allowed",
        message: "Use POST for import actions.",
        request_id: requestId,
      },
    });
  }
  try {
    const { admin, actorId } = await authenticate(request);
    let body: Json;
    try {
      body = await readBoundedJSONObject(request);
    } catch (error) {
      if (error instanceof ImportRequestError) throw error;
      throw new ImportRequestError(
        400,
        "invalid_json",
        "The request body must be valid JSON.",
      );
    }
    if (!body || typeof body !== "object" || Array.isArray(body)) {
      throw new ImportRequestError(
        400,
        "invalid_json",
        "The request body must be a JSON object.",
      );
    }
    const action = text(body.action, 40);
    logAction = action;
    logOrgId = text(body.org_id, 36).toLowerCase();
    logJobId = text(body.job_id, 36).toLowerCase();
    console.info(
      JSON.stringify({
        stage: "player_development_import_action",
        request_id: requestId,
        action,
        org_id: logOrgId,
        job_id: logJobId || undefined,
        actor_id: actorId,
      }),
    );
    const result = await handleCollectionAction(admin, actorId, body);
    return response(200, result);
  } catch (error) {
    if (error instanceof ImportRequestError) {
      console.warn(JSON.stringify({
        stage: error.internalStage ?? "player_development_import_rejected",
        request_id: requestId,
        action: logAction,
        org_id: logOrgId,
        job_id: logJobId || undefined,
        code: error.code,
        status: error.status,
        postgrest_status: error.postgrestStatus,
        postgres_code: error.postgresCode,
      }));
      return response(error.status, {
        error: {
          code: error.code,
          message: error.safeMessage,
          request_id: requestId,
        },
      });
    }
    console.error(
      JSON.stringify({
        stage: "player_development_import_failure",
        request_id: requestId,
        action: logAction,
        org_id: logOrgId,
        job_id: logJobId || undefined,
        code: "unexpected_error",
      }),
    );
    return response(500, {
      error: {
        code: "unexpected_error",
        message: "The import request could not be completed.",
        request_id: requestId,
      },
    });
  }
});
